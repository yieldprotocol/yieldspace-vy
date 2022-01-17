// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.11;

import {Math64x64} from "./Math64x64.sol";
import {Exp64x64} from "./Exp64x64.sol";

/**
 * Ethereum smart contract library implementing Yield Math model with variable yield tokens.
 */
library VariableYieldMath {
    using Math64x64 for int128;
    using Math64x64 for uint128;
    using Math64x64 for int256;
    using Math64x64 for uint256;
    using Exp64x64 for uint128;

    uint128 public constant ONE = 0x10000000000000000; // In 64.64
    uint256 public constant MAX = type(uint128).max; // Used for overflow checks

    /**
     * Calculate the amount of fyToken a user would get for given amount of VyBase.
     * https://www.desmos.com/calculator/5nf2xuy6yb
     * @param vyBaseReserves vyBase reserves amount
     * @param fyTokenReserves fyToken reserves amount
     * @param vyBaseAmount vyBase amount to be traded
     * @param timeTillMaturity time till maturity in seconds
     * @param k time till maturity coefficient, multiplied by 2^64
     * @param g fee coefficient, multiplied by 2^64
     * @param c price of vyBase in terms of Dai, multiplied by 2^64
     * @return fyTokenOut the amount of fyToken a user would get for given amount of VyBase
     */
    function fyTokenOutForVyBaseIn(
        uint128 vyBaseReserves,
        uint128 fyTokenReserves,
        uint128 vyBaseAmount,
        uint128 timeTillMaturity,
        int128 k,
        int128 g,
        int128 c
    ) public pure returns (uint128 fyTokenOut) {
        unchecked {
            require(c > 0, "YieldMath: c must be positive");

            uint128 a = _computeA(timeTillMaturity, k, g);
            // za = c * (vyBaseReserves ** a)
            uint256 za = c.mulu(vyBaseReserves.pow(a, ONE));
            require(
                za <= MAX,
                "YieldMath: Exchange rate overflow before trade"
            );

            // ya = fyTokenReserves ** a
            uint256 ya = fyTokenReserves.pow(a, ONE);

            // zx = vyBaseReserves + vyBaseAmount
            uint256 zx = uint256(vyBaseReserves) + uint256(vyBaseAmount);
            require(zx <= MAX, "YieldMath: Too much vyBase in");

            // zxa = c * (zx ** a)
            uint256 zxa = c.mulu(uint128(zx).pow(a, ONE));
            require(
                zxa <= MAX,
                "YieldMath: Exchange rate overflow after trade"
            );

            // sum = za + ya - zxa
            uint256 sum = za + ya - zxa; // z < MAX, y < MAX, a < 1. It can only underflow, not overflow.
            require(sum <= MAX, "YieldMath: Insufficient fyToken reserves");

            // result = fyTokenReserves - (sum ** (1/a))
            uint256 result = uint256(fyTokenReserves) -
                uint256(uint128(sum).pow(ONE, a));
            require(result <= MAX, "YieldMath: Rounding induced error");

            result = result > 1e12 ? result - 1e12 : 0; // Subtract error guard, flooring the result at zero

            fyTokenOut = uint128(result);
        }
    }

    /**
     * Calculate the amount of vyBase a user would get for certain amount of fyToken.
     * https://www.desmos.com/calculator/6jlrre7ybt
     * @param vyBaseReserves vyBase reserves amount
     * @param fyTokenReserves fyToken reserves amount
     * @param fyTokenAmount fyToken amount to be traded
     * @param timeTillMaturity time till maturity in seconds
     * @param k time till maturity coefficient, multiplied by 2^64
     * @param g fee coefficient, multiplied by 2^64
     * @param c price of vyBase in terms of Dai, multiplied by 2^64
     * @return the amount of VyBase a user would get for given amount of fyToken
     */
    function vyBaseOutForFyTokenIn(
        uint128 vyBaseReserves,
        uint128 fyTokenReserves,
        uint128 fyTokenAmount,
        uint128 timeTillMaturity,
        int128 k,
        int128 g,
        int128 c
    ) public pure returns (uint128) {
        unchecked {
            require(c > 0, "YieldMath: c must be positive");

            return
                _vyBaseOutForFyTokenIn(
                    vyBaseReserves,
                    fyTokenReserves,
                    fyTokenAmount,
                    _computeA(timeTillMaturity, k, g),
                    c
                );
        }
    }

    /// @dev Splitting vyBaseOutForFyTokenIn in two functions to avoid stack depth limits.
    function _vyBaseOutForFyTokenIn(
        uint128 vyBaseReserves,
        uint128 fyTokenReserves,
        uint128 fyTokenAmount,
        uint128 a,
        int128 c
    ) private pure returns (uint128) {
        unchecked {
            // invC = 1 / c
            int128 invC = c.inv();

            // za = c * (vyBaseReserves ** a)
            uint256 za = c.mulu(vyBaseReserves.pow(a, ONE));
            require(
                za <= MAX,
                "YieldMath: Exchange rate overflow before trade"
            );

            // ya = fyTokenReserves ** a
            uint256 ya = fyTokenReserves.pow(a, ONE);

            // yx = fyTokenReserves + fyTokenAmount
            uint256 yx = uint256(fyTokenReserves) + uint256(fyTokenAmount);
            require(yx <= MAX, "YieldMath: Too much fyToken in");

            // yxa = yx ** a
            uint256 yxa = uint128(yx).pow(a, ONE);

            // sum = za + ya - yxa
            uint256 sum = za + ya - yxa; // z < MAX, y < MAX, a < 1. It can only underflow, not overflow.
            require(sum <= MAX, "YieldMath: Insufficient vyBase reserves");

            // (1/c) * sum
            uint256 invCsum = invC.mulu(sum);
            require(invCsum <= MAX, "YieldMath: c too close to zero");

            // result = vyBaseReserves - (((1/c) * sum) ** (1/a))
            uint256 result = uint256(vyBaseReserves) -
                uint256(uint128(invCsum).pow(ONE, a));
            require(result <= MAX, "YieldMath: Rounding induced error");

            result = result > 1e12 ? result - 1e12 : 0; // Subtract error guard, flooring the result at zero

            return uint128(result);
        }
    }

    /**
     * Calculate the amount of fyToken a user could sell for given amount of VyBase.
     * https://www.desmos.com/calculator/0rgnmtckvy
     * @param vyBaseReserves vyBase reserves amount
     * @param fyTokenReserves fyToken reserves amount
     * @param vyBaseAmount VyBase amount to be traded
     * @param timeTillMaturity time till maturity in seconds
     * @param k time till maturity coefficient, multiplied by 2^64
     * @param g fee coefficient, multiplied by 2^64
     * @param c price of vyBase in terms of Dai, multiplied by 2^64
     * @return fyTokenIn the amount of fyToken a user could sell for given amount of VyBase
     */
    function fyTokenInForVyBaseOut(
        uint128 vyBaseReserves,
        uint128 fyTokenReserves,
        uint128 vyBaseAmount,
        uint128 timeTillMaturity,
        int128 k,
        int128 g,
        int128 c
    ) public pure returns (uint128 fyTokenIn) {
        unchecked {
            require(c > 0, "YieldMath: c must be positive");

            uint128 a = _computeA(timeTillMaturity, k, g);

            // za = c * (vyBaseReserves ** a)
            uint256 za = c.mulu(vyBaseReserves.pow(a, ONE));
            require(
                za <= MAX,
                "YieldMath: Exchange rate overflow before trade"
            );

            // ya = fyTokenReserves ** a
            uint256 ya = fyTokenReserves.pow(a, ONE);

            // zx = vyBaseReserves - vyBaseAmount
            uint256 zx = uint256(vyBaseReserves) - uint256(vyBaseAmount);
            require(zx <= MAX, "YieldMath: Too much vyBase out");

            // zxa = c * (zx ** a)
            uint256 zxa = c.mulu(uint128(zx).pow(a, ONE));
            require(
                zxa <= MAX,
                "YieldMath: Exchange rate overflow after trade"
            );

            // sum = za + ya - zxa
            uint256 sum = za + ya - zxa; // z < MAX, y < MAX, a < 1. It can only underflow, not overflow.
            require(
                sum <= MAX,
                "YieldMath: Resulting fyToken reserves too high"
            );

            // result = (sum ** (1/a)) - fyTokenReserves
            uint256 result = uint256(uint128(sum).pow(ONE, a)) -
                uint256(fyTokenReserves);
            require(result <= MAX, "YieldMath: Rounding induced error");

            result = result < MAX - 1e12 ? result + 1e12 : MAX; // Add error guard, ceiling the result at max

            fyTokenIn = uint128(result);
        }
    }

    /**
     * Calculate the amount of vyBase a user would have to pay for certain amount of fyToken.
     * https://www.desmos.com/calculator/ws5oqj8x5i
     * @param vyBaseReserves VyBase reserves amount
     * @param fyTokenReserves fyToken reserves amount
     * @param fyTokenAmount fyToken amount to be traded
     * @param timeTillMaturity time till maturity in seconds
     * @param k time till maturity coefficient, multiplied by 2^64
     * @param g fee coefficient, multiplied by 2^64
     * @param c price of vyBase in terms of Dai, multiplied by 2^64
     * @return the amount of vyBase a user would have to pay for given amount of fyToken
     */
    function vyBaseInForFyTokenOut(
        uint128 vyBaseReserves,
        uint128 fyTokenReserves,
        uint128 fyTokenAmount,
        uint128 timeTillMaturity,
        int128 k,
        int128 g,
        int128 c
    ) public pure returns (uint128) {
        unchecked {
            require(c > 0, "YieldMath: c must be positive");

            return
                _vyBaseInForFyTokenOut(
                    vyBaseReserves,
                    fyTokenReserves,
                    fyTokenAmount,
                    _computeA(timeTillMaturity, k, g),
                    c
                );

        }
    }

    // /// @dev Splitting vyBaseInForFyTokenOut in two functions to avoid stack depth limits.
    function _vyBaseInForFyTokenOut(
        uint128 vyBaseReserves,
        uint128 fyTokenReserves,
        uint128 fyTokenAmount,
        uint128 a,
        int128 c
    ) private pure returns (uint128) {
        unchecked {
            // invC = 1 / c
            int128 invC = c.inv();

            // za = c * (vyBaseReserves ** a)
            uint256 za = c.mulu(vyBaseReserves.pow(a, ONE));
            require(
                za <= MAX,
                "YieldMath: Exchange rate overflow before trade"
            );

            // ya = fyTokenReserves ** a
            uint256 ya = fyTokenReserves.pow(a, ONE);

            // yx = vyBaseReserves - vyBaseAmount
            uint256 yx = uint256(fyTokenReserves) - uint256(fyTokenAmount);
            require(yx <= MAX, "YieldMath: Too much fyToken out");

            // yxa = yx ** a
            uint256 yxa = uint128(yx).pow(a, ONE);

            // sum = za + ya - yxa
            uint256 sum = za + ya - yxa; // z < MAX, y < MAX, a < 1. It can only underflow, not overflow.
            require(
                sum <= MAX,
                "YieldMath: Resulting vyBase reserves too high"
            );

            // (1/c) * sum
            uint256 invCsum = invC.mulu(sum);
            require(invCsum <= MAX, "YieldMath: c too close to zero");

            // result = (((1/c) * sum) ** (1/a)) - vyBaseReserves
            uint256 result = uint256(uint128(invCsum).pow(ONE, a)) -
                uint256(vyBaseReserves);
            require(result <= MAX, "YieldMath: Rounding induced error");

            result = result < MAX - 1e12 ? result + 1e12 : MAX; // Add error guard, ceiling the result at max

            return uint128(result);
        }
    }

    function _computeA(
        uint128 timeTillMaturity,
        int128 k,
        int128 g
    ) private pure returns (uint128) {
        // t = k * timeTillMaturity
        int128 t = k.mul(timeTillMaturity.fromUInt());
        require(t >= 0, "YieldMath: t must be positive"); // Meaning neither T or k can be negative

        // a = (1 - gt)
        int128 a = int128(ONE).sub(g.mul(t));
        require(a > 0, "YieldMath: Too far from maturity");
        require(a <= int128(ONE), "YieldMath: g must be positive");

        return uint128(a);
    }

    /**
     * Calculate the amount of fyToken a user would get for given amount of VyBase.
     * A normalization parameter is taken to normalize the exchange rate at a certain value.
     * This is used for liquidity pools to be initialized with balanced reserves.
     * @param vyBaseReserves vyBase reserves amount
     * @param fyTokenReserves fyToken reserves amount
     * @param vyBaseAmount VyBase amount to be traded
     * @param timeTillMaturity time till maturity in seconds
     * @param k time till maturity coefficient, multiplied by 2^64
     * @param g fee coefficient, multiplied by 2^64
     * @param c0 price of vyBase in terms of vyBase as it was at protocol
     *        initialization time, multiplied by 2^64
     * @param c price of vyBase in terms of Dai, multiplied by 2^64
     * @return fyTokenOut the amount of fyToken a user would get for given amount of VyBase
     */
    function fyTokenOutForVyBaseInNormalized(
        uint128 vyBaseReserves,
        uint128 fyTokenReserves,
        uint128 vyBaseAmount,
        uint128 timeTillMaturity,
        int128 k,
        int128 g,
        int128 c0,
        int128 c
    ) external pure returns (uint128 fyTokenOut) {
        unchecked {
            uint256 normalizedVyBaseReserves = c0.mulu(vyBaseReserves);
            require(
                normalizedVyBaseReserves <= MAX,
                "YieldMath: Overflow on reserve normalization"
            );

            uint256 normalizedVyBaseAmount = c0.mulu(vyBaseAmount);
            require(
                normalizedVyBaseAmount <= MAX,
                "YieldMath: Overflow on trade normalization"
            );

            fyTokenOut = fyTokenOutForVyBaseIn(
                uint128(normalizedVyBaseReserves),
                fyTokenReserves,
                uint128(normalizedVyBaseAmount),
                timeTillMaturity,
                k,
                g,
                c.div(c0)
            );
        }
    }

    /**
     * Calculate the amount of vyBase a user would get for certain amount of fyToken.
     * A normalization parameter is taken to normalize the exchange rate at a certain value.
     * This is used for liquidity pools to be initialized with balanced reserves.
     * @param vyBaseReserves vyBase reserves amount
     * @param fyTokenReserves fyToken reserves amount
     * @param fyTokenAmount fyToken amount to be traded
     * @param timeTillMaturity time till maturity in seconds
     * @param k time till maturity coefficient, multiplied by 2^64
     * @param g fee coefficient, multiplied by 2^64
     * @param c0 price of vyBase in terms of Dai as it was at protocol
     *        initialization time, multiplied by 2^64
     * @param c price of vyBase in terms of Dai, multiplied by 2^64
     * @return vyBaseOut the amount of vyBase a user would get for given amount of fyToken
     */
    function vyBaseOutForFyTokenInNormalized(
        uint128 vyBaseReserves,
        uint128 fyTokenReserves,
        uint128 fyTokenAmount,
        uint128 timeTillMaturity,
        int128 k,
        int128 g,
        int128 c0,
        int128 c
    ) external pure returns (uint128 vyBaseOut) {
        unchecked {
            uint256 normalizedVyBaseReserves = c0.mulu(vyBaseReserves);
            require(
                normalizedVyBaseReserves <= MAX,
                "YieldMath: Overflow on reserve normalization"
            );

            uint256 result = c0.inv().mulu(
                vyBaseOutForFyTokenIn(
                    uint128(normalizedVyBaseReserves),
                    fyTokenReserves,
                    fyTokenAmount,
                    timeTillMaturity,
                    k,
                    g,
                    c.div(c0)
                )
            );
            require(
                result <= MAX,
                "YieldMath: Overflow on result normalization"
            );

            vyBaseOut = uint128(result);
        }
    }

    /**
     * Calculate the amount of fyToken a user could sell for given amount of VyBase.
     *
     * @param vyBaseReserves vyBase reserves amount
     * @param fyTokenReserves fyToken reserves amount
     * @param vyBaseAmount vyBase amount to be traded
     * @param timeTillMaturity time till maturity in seconds
     * @param k time till maturity coefficient, multiplied by 2^64
     * @param g fee coefficient, multiplied by 2^64
     * @param c0 price of vyBase in terms of Dai as it was at protocol
     *        initialization time, multiplied by 2^64
     * @param c price of vyBase in terms of Dai, multiplied by 2^64
     * @return fyTokenIn the amount of fyToken a user could sell for given amount of VyBase
     */
    function fyTokenInForVyBaseOutNormalized(
        uint128 vyBaseReserves,
        uint128 fyTokenReserves,
        uint128 vyBaseAmount,
        uint128 timeTillMaturity,
        int128 k,
        int128 g,
        int128 c0,
        int128 c
    ) external pure returns (uint128 fyTokenIn) {
        unchecked {
            uint256 normalizedVyBaseReserves = c0.mulu(vyBaseReserves);
            require(
                normalizedVyBaseReserves <= MAX,
                "YieldMath: Overflow on reserve normalization"
            );

            uint256 normalizedVyBaseAmount = c0.mulu(vyBaseAmount);
            require(
                normalizedVyBaseAmount <= MAX,
                "YieldMath: Overflow on trade normalization"
            );

            fyTokenIn = fyTokenInForVyBaseOut(
                uint128(normalizedVyBaseReserves),
                fyTokenReserves,
                uint128(normalizedVyBaseAmount),
                timeTillMaturity,
                k,
                g,
                c.div(c0)
            );
        }
    }

    /**
     * Calculate the amount of VyBase a user would have to pay for certain amount of
     * fyToken.
     *
     * @param vyBaseReserves vyBase reserves amount
     * @param fyTokenReserves fyToken reserves amount
     * @param fyTokenAmount fyToken amount to be traded
     * @param timeTillMaturity time till maturity in seconds
     * @param k time till maturity coefficient, multiplied by 2^64
     * @param g fee coefficient, multiplied by 2^64
     * @param c0 price of vyBase in terms of VyBase as it was at protocol
     *        initialization time, multiplied by 2^64
     * @param c price of vyBase in terms of Dai, multiplied by 2^64
     * @return vyBaseIn the amount of vyBase a user would have to pay for given amount of fyToken
     */
    function vyBaseInForFyTokenOutNormalized(
        uint128 vyBaseReserves,
        uint128 fyTokenReserves,
        uint128 fyTokenAmount,
        uint128 timeTillMaturity,
        int128 k,
        int128 g,
        int128 c0,
        int128 c
    ) external pure returns (uint128 vyBaseIn) {
        unchecked {
            uint256 normalizedVyBaseReserves = c0.mulu(vyBaseReserves);
            require(
                normalizedVyBaseReserves <= MAX,
                "YieldMath: Overflow on reserve normalization"
            );

            uint256 result = c0.inv().mulu(
                vyBaseInForFyTokenOut(
                    uint128(normalizedVyBaseReserves),
                    fyTokenReserves,
                    fyTokenAmount,
                    timeTillMaturity,
                    k,
                    g,
                    c.div(c0)
                )
            );
            require(
                result <= MAX,
                "YieldMath: Overflow on result normalization"
            );

            vyBaseIn = uint128(result);
        }
    }

    /**
     * Estimate in VyBase the value of reserves at protocol initialization time.
     *
     * @param vyBaseReserves vyBase reserves amount
     * @param fyTokenReserves fyToken reserves amount
     * @param timeTillMaturity time till maturity in seconds
     * @param k time till maturity coefficient, multiplied by 2^64
     * @param c0 price of vyBase in terms of Dai, multiplied by 2^64
     * @return initialReserves estimated value of reserves
     */
    function initialReservesValue(
        uint128 vyBaseReserves,
        uint128 fyTokenReserves,
        uint128 timeTillMaturity,
        int128 k,
        int128 c0
    ) external pure returns (uint128 initialReserves) {
        unchecked {
            uint256 normalizedVyBaseReserves = c0.mulu(vyBaseReserves);
            require(normalizedVyBaseReserves <= MAX);

            // a = (1 - k * timeTillMaturity)
            int128 a = int128(ONE).sub(k.mul(timeTillMaturity.fromUInt()));
            require(a > 0);

            uint256 sum = (uint256(
                uint128(normalizedVyBaseReserves).pow(uint128(a), ONE)
            ) + uint256(fyTokenReserves.pow(uint128(a), ONE))) >> 1;
            require(sum <= MAX);

            uint256 result = uint256(uint128(sum).pow(ONE, uint128(a))) << 1;
            require(result <= MAX);

            initialReserves = uint128(result);
        }
    }
}
