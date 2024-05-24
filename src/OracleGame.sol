// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ISupraOraclePull} from "./interfaces/SupraOracle.sol";

contract OracleGame {
    // The oracle contract
    ISupraOraclePull public immutable oracle;

    uint256 public constant pairDuration = 1 days;
    uint256 public constant guessWaitTime = 1 hours;

    uint256 public immutable startTime;

    uint256[] public allPairs;
    int256 public currentPairIndex = -1;

    mapping(address => uint256) public userPoints;
    mapping(address => bool) public userParticipated;

    struct UserGuess {
        uint256 pair;
        uint256 timestamp;
        uint256 price;
        bool rewarded;
    }

    struct PriceGuess {
        uint256 timestamp;
        uint256 price;
        address nextGuesser; // linked list
    }

    struct PairGuesses {
        address firstGuesser; // first guesser in the linked list
        address lastGuesser; // last guesser in the linked list
        mapping(address => PriceGuess) guesses;
        uint256 lastTimestamp;
    }

    mapping(uint256 => PairGuesses) public priceGuesses;

    event GuessPairPrice(address indexed guesser, uint256 indexed pair, uint256 price);
    event RewardPairGuess(
        address indexed guesser, uint256 indexed pair, uint256 guessPrice, uint256 actualPrice, uint256 points
    );

    constructor(address oracle_, uint256[] memory pairs_, uint256 startTime_) {
        oracle = ISupraOraclePull(oracle_);
        allPairs = pairs_;
        startTime = startTime_;
    }

    // price is specified in 18 decimals scale
    function guessPairPrice(uint256 price) external {
        require(block.timestamp >= startTime, "Game has not started yet");
        require(price > 0, "Price must be greater than 0");

        _checkForNextPair();

        uint256 currentPair = allPairs[uint256(currentPairIndex)];

        require(priceGuesses[currentPair].guesses[msg.sender].price == 0, "Already guessed");

        priceGuesses[currentPair].guesses[msg.sender] =
            PriceGuess({timestamp: block.timestamp, price: price, nextGuesser: address(0)});

        if (priceGuesses[currentPair].firstGuesser == address(0)) {
            // setting the first guesser in the linked list
            priceGuesses[currentPair].firstGuesser = msg.sender;
        } else {
            // setting the next guesser in the linked list
            priceGuesses[currentPair].guesses[priceGuesses[currentPair].lastGuesser].nextGuesser = msg.sender;
        }

        // updating the last guesser in the linked list
        priceGuesses[currentPair].lastGuesser = msg.sender;

        userParticipated[msg.sender] = true;

        emit GuessPairPrice(msg.sender, currentPair, price);
    }

    function getUserGuesses(address user) public view returns (UserGuess[] memory) {
        uint256 length = uint256(currentPairIndex) + 1;
        UserGuess[] memory userGuesses = new UserGuess[](length);

        for (uint256 i = 0; i < length; ++i) {
            uint256 pair = allPairs[i];
            uint256 lastTimestamp = priceGuesses[pair].lastTimestamp;
            PriceGuess storage guess = priceGuesses[pair].guesses[user];

            if (guess.price != 0) {
                userGuesses[i] = UserGuess({
                    pair: pair,
                    timestamp: guess.timestamp,
                    price: guess.price,
                    rewarded: lastTimestamp > 0 && lastTimestamp - guess.timestamp > guessWaitTime
                });
            }
        }

        return userGuesses;
    }

    function getUserParticipation(address[] calldata users) public view returns (bool[] memory) {
        bool[] memory participation = new bool[](users.length);

        for (uint256 i = 0; i < users.length; ++i) {
            participation[i] = userParticipated[users[i]];
        }

        return participation;
    }

    // Get the prices of a pairs from oracle data
    function pullPairPrices(bytes calldata _bytesProof) public {
        require(block.timestamp >= startTime && currentPairIndex >= 0, "Game has not started yet");

        uint256 previousPair;
        uint256 currentPair = allPairs[uint256(currentPairIndex)];
        if (currentPairIndex > 0) {
            previousPair = allPairs[uint256(currentPairIndex - 1)];
        }

        ISupraOraclePull.PriceData memory prices = oracle.verifyOracleProof(_bytesProof);
        int256 pair = -1;

        for (uint256 i = 0; i < prices.pairs.length; ++i) {
            if (currentPairIndex > 0 && prices.pairs[i] == previousPair) {
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
        int256 periodsPassed = int256((block.timestamp - startTime) / pairDuration);

        if (periodsPassed > currentPairIndex) {
            require(periodsPassed < int256(allPairs.length), "Game has ended");

            currentPairIndex = periodsPassed;
        }
    }

    function _processPairGuesses(uint256 pair, uint256 price, uint256 decimals) internal {
        PairGuesses storage pairGuesses = priceGuesses[pair];
        address guesser = pairGuesses.firstGuesser;

        if (guesser != address(0)) {
            if (decimals > 18) {
                price = price / (10 ** (decimals - 18));
            }
            if (decimals < 18) {
                price = price * (10 ** (18 - decimals));
            }

            while (guesser != address(0)) {
                PriceGuess storage guess = pairGuesses.guesses[guesser];

                if (block.timestamp - guess.timestamp > guessWaitTime) {
                    // 100% for exact guess, 50% for withing 1% difference, 25% for within 2% difference, and so on
                    uint256 diff = guess.price > price ? guess.price - price : price - guess.price;
                    uint256 percentage = diff == 0 ? 0 : 1 + (diff * 100) / price;
                    uint256 points = 1000000 / (2 ** (percentage));
                    userPoints[guesser] += points;

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
}
