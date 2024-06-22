// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import {ISupraOraclePull} from "./interfaces/SupraOracle.sol";
import "./OracleGameStorage.sol";

contract OracleGame is Initializable, UUPSUpgradeable, AccessControlUpgradeable {
    using OracleGameStorage for OracleGameStorage.Storage;

    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    event GuessPairPrice(address indexed guesser, uint256 indexed pair, uint256 price);
    event RewardPairGuess(
        address indexed guesser, uint256 indexed pair, uint256 guessPrice, uint256 actualPrice, uint256 points
    );

    function initialize(address oracle_, uint256[] memory pairs_, uint256 startTime_, address admin)
        public
        initializer
    {
        __AccessControl_init();
        __UUPSUpgradeable_init();

        OracleGameStorage.Storage storage s = OracleGameStorage.getStorage();
        require(address(s.oracle) == address(0), "Already initialized");
        s.oracle = ISupraOraclePull(oracle_);
        s.allPairs = pairs_;
        s.startTime = startTime_;
        s.currentPairIndex = -1;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}

    function guessPairPrice(uint256 price) external {
        OracleGameStorage.Storage storage s = OracleGameStorage.getStorage();

        require(block.timestamp >= s.startTime, "Game has not started yet");
        require(price > 0, "Price must be greater than 0");

        _checkForNextPair();

        uint256 currentPair = s.allPairs[uint256(s.currentPairIndex)];

        require(s.priceGuesses[currentPair].guesses[msg.sender].price == 0, "Already guessed");

        s.priceGuesses[currentPair].guesses[msg.sender] =
            OracleGameStorage.PriceGuess({timestamp: block.timestamp, price: price, nextGuesser: address(0)});

        if (s.priceGuesses[currentPair].firstGuesser == address(0)) {
            s.priceGuesses[currentPair].firstGuesser = msg.sender;
        } else {
            s.priceGuesses[currentPair].guesses[s.priceGuesses[currentPair].lastGuesser].nextGuesser = msg.sender;
        }

        s.priceGuesses[currentPair].lastGuesser = msg.sender;
        s.userParticipated[msg.sender] = true;

        emit GuessPairPrice(msg.sender, currentPair, price);
    }

    function getUserGuesses(address user) public view returns (OracleGameStorage.UserGuess[] memory) {
        OracleGameStorage.Storage storage s = OracleGameStorage.getStorage();

        uint256 length = uint256(s.currentPairIndex) + 1;
        OracleGameStorage.UserGuess[] memory userGuesses = new OracleGameStorage.UserGuess[](length);

        for (uint256 i = 0; i < length; ++i) {
            uint256 pair = s.allPairs[i];
            uint256 lastTimestamp = s.priceGuesses[pair].lastTimestamp;
            OracleGameStorage.PriceGuess storage guess = s.priceGuesses[pair].guesses[user];

            if (guess.price != 0) {
                userGuesses[i] = OracleGameStorage.UserGuess({
                    pair: pair,
                    timestamp: guess.timestamp,
                    price: guess.price,
                    rewarded: lastTimestamp > 0 && lastTimestamp - guess.timestamp > s.guessWaitTime
                });
            }
        }

        return userGuesses;
    }

    function getUserParticipation(address[] calldata users) public view returns (bool[] memory) {
        OracleGameStorage.Storage storage s = OracleGameStorage.getStorage();

        bool[] memory participation = new bool[](users.length);

        for (uint256 i = 0; i < users.length; ++i) {
            participation[i] = s.userParticipated[users[i]];
        }

        return participation;
    }

    function pullPairPrices(bytes calldata _bytesProof) public {
        OracleGameStorage.Storage storage s = OracleGameStorage.getStorage();

        require(block.timestamp >= s.startTime && s.currentPairIndex >= 0, "Game has not started yet");

        uint256 previousPair;
        uint256 currentPair = s.allPairs[uint256(s.currentPairIndex)];
        if (s.currentPairIndex > 0) {
            previousPair = s.allPairs[uint256(s.currentPairIndex - 1)];
        }

        ISupraOraclePull.PriceData memory prices = s.oracle.verifyOracleProof(_bytesProof);
        int256 pair = -1;

        for (uint256 i = 0; i < prices.pairs.length; ++i) {
            if (s.currentPairIndex > 0 && prices.pairs[i] == previousPair) {
                _processPairGuesses(previousPair, prices.prices[i], prices.decimals[i]);
            }
            if (prices.pairs[i] == currentPair) {
                _processPairGuesses(currentPair, prices.prices[i], prices.decimals[i]);
                pair = int256(i);
            }
        }

        require(pair != -1, "Pair not found");
    }

    function _checkForNextPair() internal {
        OracleGameStorage.Storage storage s = OracleGameStorage.getStorage();

        int256 periodsPassed = int256((block.timestamp - s.startTime) / s.pairDuration);

        if (periodsPassed > s.currentPairIndex) {
            require(periodsPassed < int256(s.allPairs.length), "Game has ended");

            s.currentPairIndex = periodsPassed;
        }
    }

    function _processPairGuesses(uint256 pair, uint256 price, uint256 decimals) internal {
        OracleGameStorage.Storage storage s = OracleGameStorage.getStorage();

        OracleGameStorage.PairGuesses storage pairGuesses = s.priceGuesses[pair];
        address guesser = pairGuesses.firstGuesser;

        if (guesser != address(0)) {
            if (decimals > 18) {
                price = price / (10 ** (decimals - 18));
            }
            if (decimals < 18) {
                price = price * (10 ** (18 - decimals));
            }

            while (guesser != address(0)) {
                OracleGameStorage.PriceGuess storage guess = pairGuesses.guesses[guesser];

                if (block.timestamp - guess.timestamp > s.guessWaitTime) {
                    uint256 diff = guess.price > price ? guess.price - price : price - guess.price;
                    uint256 percentage = diff == 0 ? 0 : 1 + (diff * 100) / price;
                    uint256 points = 1000000 / (2 ** (percentage));
                    s.userPoints[guesser] += points;

                    emit RewardPairGuess(guesser, pair, guess.price, price, points);

                    guesser = guess.nextGuesser;
                } else {
                    pairGuesses.firstGuesser = guesser;
                    break;
                }
            }

            if (guesser == address(0)) {
                pairGuesses.firstGuesser = address(0);
                pairGuesses.lastGuesser = address(0);
            }

            pairGuesses.lastTimestamp = block.timestamp;
        }
    }

    // View functions for storage variables
    function oracle() public view returns (address) {
        OracleGameStorage.Storage storage s = OracleGameStorage.getStorage();
        return address(s.oracle);
    }

    function startTime() public view returns (uint256) {
        OracleGameStorage.Storage storage s = OracleGameStorage.getStorage();
        return s.startTime;
    }

    function getAllPairs() public view returns (uint256[] memory) {
        OracleGameStorage.Storage storage s = OracleGameStorage.getStorage();
        return s.allPairs;
    }

    function allPairs(uint256 index) public view returns (uint256) {
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

    function guessWaitTime() public view returns (uint256) {
        OracleGameStorage.Storage storage s = OracleGameStorage.getStorage();
        return s.guessWaitTime;
    }

    function userPoints(address user) public view returns (uint256) {
        OracleGameStorage.Storage storage s = OracleGameStorage.getStorage();
        return s.userPoints[user];
    }

    function userParticipated(address user) public view returns (bool) {
        OracleGameStorage.Storage storage s = OracleGameStorage.getStorage();
        return s.userParticipated[user];
    }

    function firstGuesser(uint256 pair) public view returns (address) {
        OracleGameStorage.Storage storage s = OracleGameStorage.getStorage();
        return s.priceGuesses[pair].firstGuesser;
    }

    function lastGuesser(uint256 pair) public view returns (address) {
        OracleGameStorage.Storage storage s = OracleGameStorage.getStorage();
        return s.priceGuesses[pair].lastGuesser;
    }

    function getGuess(uint256 pair, address user) public view returns (OracleGameStorage.PriceGuess memory) {
        OracleGameStorage.Storage storage s = OracleGameStorage.getStorage();
        return s.priceGuesses[pair].guesses[user];
    }

    function getLastTimestamp(uint256 pair) public view returns (uint256) {
        OracleGameStorage.Storage storage s = OracleGameStorage.getStorage();
        return s.priceGuesses[pair].lastTimestamp;
    }
}
