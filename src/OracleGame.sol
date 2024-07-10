// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import {ISupraOraclePull} from "./interfaces/SupraOracle.sol";
import "./OracleGameStorage.sol";
import "./CheckInStorage.sol";

contract OracleGame is Initializable, UUPSUpgradeable, AccessControlUpgradeable {
    using OracleGameStorage for OracleGameStorage.Storage;

    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    event PriceMovementPrediction(address indexed user, uint256 indexed pair, bool isLong, uint256 timestamp);
    event RevealPrediction(address indexed user, uint256 indexed pair, bool isLong, uint256 timestamp, bool isCorrect);

    /**
     * @notice Initialize the contract
     * @param oracle_ The address of the oracle contract
     * @param checkIn_ The address of the checkin contract
     * @param pairs_ The list of pairs to predict
     * @param startTime_ The start time of the game
     * @param pairDuration_ The duration of each pair
     * @param waitTime The time to wait before revealing the prediction
     * @param cooldownTime The time to wait before making another prediction
     * @param admin The address of the admin
     */
    function initialize(
        address oracle_,
        address checkIn_,
        uint256[] memory pairs_,
        uint256 startTime_,
        uint256 pairDuration_,
        uint256 waitTime,
        uint256 cooldownTime,
        address admin
    ) public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();

        OracleGameStorage.Storage storage s = OracleGameStorage.getStorage();
        require(address(s.oracle) == address(0), "Already initialized");
        s.oracle = ISupraOraclePull(oracle_);
        s.checkin = ICheckIn(checkIn_);
        s.allPairs = pairs_;
        s.startTime = startTime_;
        s.pairDuration = pairDuration_;
        s.predictionWaitTime = waitTime;
        s.predictionCooldown = cooldownTime;
        s.currentPairIndex = -1;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);
    }

    /**
     * @notice Upgrade the implementation of the contract
     * @param newImplementation The address of the new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}

    /**
     * @notice Predict the price movement of the current pair
     * @param pairIndex The index of the pair to predict
     * @param isLong The direction of the price movement
     */
    function predictPriceMovement(uint256 pairIndex, bool isLong) external {
        OracleGameStorage.Storage storage s = OracleGameStorage.getStorage();

        require(block.timestamp >= s.startTime, "Game has not started yet");

        _checkForNextPair();

        require(pairIndex <= uint256(s.currentPairIndex), "Pair has not started yet");

        uint256 pair = s.allPairs[pairIndex];

        OracleGameStorage.Predictions storage predictions = s.predictions[pair];
        OracleGameStorage.PriceMovement storage prediction = predictions.priceMovements[msg.sender];

        require(block.timestamp - prediction.timestamp >= s.predictionCooldown, "Wait for cooldown");

        prediction.timestamp = block.timestamp;
        prediction.originalPrice = s.pairPrices[pair];
        prediction.isLong = isLong;
        prediction.revealed = false;
        prediction.next = address(0);

        if (predictions.first == address(0)) {
            predictions.first = msg.sender;
        } else {
            predictions.priceMovements[s.predictions[pair].last].next = msg.sender;
        }

        predictions.last = msg.sender;
        s.userParticipated[msg.sender] = true;

        emit PriceMovementPrediction(msg.sender, pair, isLong, block.timestamp);
    }

    /**
     * @notice Get the participation status of the users
     * @param users The list of users
     * @return participation The participation status of the users
     */
    function getUserParticipation(address[] calldata users) public view returns (bool[] memory) {
        OracleGameStorage.Storage storage s = OracleGameStorage.getStorage();

        bool[] memory participation = new bool[](users.length);

        for (uint256 i = 0; i < users.length; ++i) {
            participation[i] = s.userParticipated[users[i]];
        }

        return participation;
    }

    /**
     * @notice Update the pair prices and reveal the predictions
     * @param _bytesProof The proof of the oracle data
     */
    function pullPairPrices(bytes calldata _bytesProof) public {
        OracleGameStorage.Storage storage s = OracleGameStorage.getStorage();

        require(block.timestamp >= s.startTime && s.currentPairIndex >= 0, "Game has not started yet");

        ISupraOraclePull.PriceData memory prices = s.oracle.verifyOracleProof(_bytesProof);

        for (uint256 i = 0; i < prices.pairs.length; ++i) {
            uint256 pair = prices.pairs[i];
            uint256 price = prices.prices[i];
            uint256 decimals = prices.decimals[i];

            if (decimals > 18) {
                price = price / (10 ** (decimals - 18));
            }
            if (decimals < 18) {
                price = price * (10 ** (18 - decimals));
            }

            s.pairPrices[pair] = price;
            _processPredictions(pair, price);
        }
    }

    function _checkForNextPair() internal {
        OracleGameStorage.Storage storage s = OracleGameStorage.getStorage();

        int256 periodsPassed = int256((block.timestamp - s.startTime) / s.pairDuration);

        if (periodsPassed > s.currentPairIndex) {
            require(periodsPassed < int256(s.allPairs.length), "Game has ended");

            s.currentPairIndex = periodsPassed;
        }
    }

    function _processPredictions(uint256 pair, uint256 price) internal {
        OracleGameStorage.Storage storage s = OracleGameStorage.getStorage();

        OracleGameStorage.Predictions storage predictions = s.predictions[pair];
        address user = predictions.first;

        if (user != address(0)) {
            while (user != address(0)) {
                OracleGameStorage.PriceMovement storage prediction = predictions.priceMovements[user];

                if (block.timestamp - prediction.timestamp > s.predictionWaitTime) {
                    bool isCorrect =
                        prediction.isLong ? (price > prediction.originalPrice) : (price < prediction.originalPrice);
                    // for participation
                    s.checkin.incrementTaskPoints(user, CheckInStorage.Task.SUPRA);

                    if (isCorrect) {
                        // for correct prediction
                        s.checkin.incrementTaskPoints(user, CheckInStorage.Task.SUPRA);
                    }

                    emit RevealPrediction(user, pair, prediction.isLong, prediction.timestamp, isCorrect);

                    prediction.revealed = true;
                    user = prediction.next;
                } else {
                    predictions.first = user;
                    break;
                }
            }

            if (user == address(0)) {
                predictions.first = address(0);
                predictions.last = address(0);
            }

            predictions.lastTimestamp = block.timestamp;
        }
    }

    // View functions for storage variables
    function oracle() public view returns (address) {
        OracleGameStorage.Storage storage s = OracleGameStorage.getStorage();
        return address(s.oracle);
    }

    function checkIn() public view returns (address) {
        OracleGameStorage.Storage storage s = OracleGameStorage.getStorage();
        return address(s.checkin);
    }

    function startTime() public view returns (uint256) {
        OracleGameStorage.Storage storage s = OracleGameStorage.getStorage();
        return s.startTime;
    }

    function getAllPairs() public view returns (uint256[] memory) {
        OracleGameStorage.Storage storage s = OracleGameStorage.getStorage();
        return s.allPairs;
    }

    function getPair(uint256 index) public view returns (uint256) {
        OracleGameStorage.Storage storage s = OracleGameStorage.getStorage();
        return s.allPairs[index];
    }

    function currentPairIndex() public view returns (int256) {
        OracleGameStorage.Storage storage s = OracleGameStorage.getStorage();
        return s.currentPairIndex;
    }

    function pairDuration() public view returns (uint256) {
        OracleGameStorage.Storage storage s = OracleGameStorage.getStorage();
        return s.pairDuration;
    }

    function predictionWaitTime() public view returns (uint256) {
        OracleGameStorage.Storage storage s = OracleGameStorage.getStorage();
        return s.predictionWaitTime;
    }

    function predictionCooldown() public view returns (uint256) {
        OracleGameStorage.Storage storage s = OracleGameStorage.getStorage();
        return s.predictionCooldown;
    }

    function userParticipated(address user) public view returns (bool) {
        OracleGameStorage.Storage storage s = OracleGameStorage.getStorage();
        return s.userParticipated[user];
    }

    function firstPrediction(uint256 pair) public view returns (address) {
        OracleGameStorage.Storage storage s = OracleGameStorage.getStorage();
        return s.predictions[pair].first;
    }

    function lastPrediction(uint256 pair) public view returns (address) {
        OracleGameStorage.Storage storage s = OracleGameStorage.getStorage();
        return s.predictions[pair].last;
    }

    function getPriceMovement(uint256 pair, address user)
        public
        view
        returns (OracleGameStorage.PriceMovement memory)
    {
        OracleGameStorage.Storage storage s = OracleGameStorage.getStorage();
        return s.predictions[pair].priceMovements[user];
    }

    function getLastTimestamp(uint256 pair) public view returns (uint256) {
        OracleGameStorage.Storage storage s = OracleGameStorage.getStorage();
        return s.predictions[pair].lastTimestamp;
    }
}
