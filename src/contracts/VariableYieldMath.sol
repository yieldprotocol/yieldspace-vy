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
     * Calculate the amount of fyToken a user would get for given amount of shares.
     * https://www.desmos.com/calculator/7iebbri94t
     * @param sharesReserves yield bearing vault shares reserve amount
     * @param fyTokenReserves fyToken reserves amount
     * @param sharesAmount shares amount to be traded
     * @param timeTillMaturity time till maturity in seconds e.g. 90 days in seconds
     * @param k time till maturity coefficient, multiplied by 2^64.  e.g. 25 years in seconds
     * @param g fee coefficient, multiplied by 2^64 -- sb under 1.0 for selling shares to pool
     * @param c price of shares in terms of their base, multiplied by 2^64
     * @param mu (μ) Normalization factor -- starts as c at initialization
     * @return fyTokenOut the amount of fyToken a user would get for given amount of shares
     *
     *          (                        sum                           )
     *            (    Za        )   ( Ya  )   (       Zxa         )   (   invA   )
     * dy = y - ( c/μ * (μz)^(1-t) + y^(1-t) - c/μ * (μz + μdx)^(1-t) )^(1 / (1 - t))
     *
     */
    function fyTokenOutForSharesIn(
        uint128 sharesReserves, // z
        uint128 fyTokenReserves, // x
        uint128 sharesAmount, // dx
        uint128 timeTillMaturity,
        int128 k,
        int128 g,
        int128 c,
        int128 mu
    ) public pure returns (uint128 fyTokenOut) {
        unchecked {
            require(c > 0 && mu > 0, "YieldMath: c and mu must be positive");

            return
                _fyTokenOutForSharesIn(
                    sharesReserves,
                    fyTokenReserves,
                    sharesAmount,
                    _computeA(timeTillMaturity, k, g),
                    c,
                    mu
                );
        }
    }

    function _fyTokenOutForSharesIn(
        uint128 sharesReserves, // z
        uint128 fyTokenReserves, // x
        uint128 sharesAmount, // dx
        uint128 a,
        int128 c,
        int128 mu
    ) internal pure returns (uint128) {
        // normalizedSharesReserves = μ * sharesReserves
        uint256 normalizedSharesReserves = mu.mulu(sharesReserves);
        require(
            normalizedSharesReserves <= MAX,
            "YieldMath: Exchange rate overflow before trade"
        );

        // za = c/μ * (normalizedSharesReserves ** a)
        uint256 za = c.div(mu).mulu(
            uint128(normalizedSharesReserves).pow(a, ONE)
        );
        require(za <= MAX, "YieldMath: Exchange rate overflow before trade");

        // ya = fyTokenReserves ** a
        uint256 ya = fyTokenReserves.pow(a, ONE);

        // normalizedSharesAmount = μ * sharesAmount
        uint256 normalizedSharesAmount = mu.mulu(sharesAmount);
        require(
            normalizedSharesAmount <= MAX,
            "YieldMath: Exchange rate overflow before trade"
        );

        // zx = normalizedBaseReserves + sharesAmount * μ
        uint256 zx = normalizedSharesReserves + normalizedSharesAmount;
        require(zx <= MAX, "YieldMath: Too much shares in");

        // zxa = c/μ * zx ** a
        uint256 zxa = c.div(mu).mulu(uint128(zx).pow(a, ONE));
        require(zxa <= MAX, "YieldMath: Exchange rate overflow after trade");

        // sum = za + ya - zxa
        uint256 sum = za + ya - zxa; // z < MAX, y < MAX, a < 1. It can only underflow, not overflow.
        require(sum <= MAX, "YieldMath: Insufficient fyToken reserves");

        // result = fyTokenReserves - (sum ** (1/a))
        uint256 result = uint256(fyTokenReserves) -
            uint256(uint128(sum).pow(ONE, a));
        require(result <= MAX, "YieldMath: Rounding induced error");

        result = result < MAX - 1e12 ? result + 1e12 : MAX; // Add error guard, ceiling the result at max

        return uint128(result);
    }

    /**
     * Calculate the amount of shares a user would get for certain amount of fyToken.
     * https://www.desmos.com/calculator/o64taldxhx
     * @param sharesReserves shares reserves amount
     * @param fyTokenReserves fyToken reserves amount
     * @param fyTokenAmount fyToken amount to be traded
     * @param timeTillMaturity time till maturity in seconds
     * @param k time till maturity coefficient, multiplied by 2^64
     * @param g fee coefficient, multiplied by 2^64
     * @param c price of shares in terms of Dai, multiplied by 2^64
     * @param mu (μ) Normalization factor -- starts as c at initialization
     * @return the amount of Shares a user would get for given amount of fyToken
     *
     *                (                      sum                                       )
     *                  (       Za           )   ( Ya  )    (    Yxa     )               (   invA   )
     * dz = z - 1/μ  * ( ( (c / μ) * (μz)^(1-t) + y^(1-t) -  (y + x)^(1-t) ) / (c / μ) )^(1 / (1 - t))
     */
    function sharesOutForFyTokenIn(
        uint128 sharesReserves,
        uint128 fyTokenReserves,
        uint128 fyTokenAmount,
        uint128 timeTillMaturity,
        int128 k,
        int128 g,
        int128 c,
        int128 mu
    ) public pure returns (uint128) {
        unchecked {
            require(c > 0, "YieldMath: c must be positive");

            return
                _sharesOutForFyTokenIn(
                    sharesReserves,
                    fyTokenReserves,
                    fyTokenAmount,
                    _computeA(timeTillMaturity, k, g),
                    c,
                    mu
                );
        }
    }

    /// @dev Splitting sharesOutForFyTokenIn in two functions to avoid stack depth limits.
    function _sharesOutForFyTokenIn(
        uint128 sharesReserves,
        uint128 fyTokenReserves,
        uint128 fyTokenAmount,
        uint128 a,
        int128 c,
        int128 mu
    ) private pure returns (uint128 result) {
        // normalizedSharesReserves = μ * sharesReserves
        uint256 normalizedSharesReserves = mu.mulu(sharesReserves);
        require(
            normalizedSharesReserves <= MAX,
            "YieldMath: Exchange rate overflow before trade"
        );

        // za = c/μ * (normalizedSharesReserves ** a)
        uint256 za = c.div(mu).mulu(
            uint128(normalizedSharesReserves).pow(a, ONE)
        );
        require(za <= MAX, "YieldMath: Exchange rate overflow before trade");

        // ya = fyTokenReserves ** a
        uint256 ya = fyTokenReserves.pow(a, ONE);

        // yxa = (fyTokenReserves + x) ** a   # x is aka Δy
        uint256 yxa = (fyTokenReserves + fyTokenAmount).pow(a, ONE);

        uint256 subtotalLeft = (za + ya - yxa);
        require(
            subtotalLeft <= MAX,
            "YieldMath: Exchange rate overflow before trade"
        );

        int128 subtotal = subtotalLeft.divu(uint128(c.div(mu)));
        uint128 subtotalRaised = uint128(subtotal).pow(
            uint128(ONE),
            uint128(a)
        );
        int128 invMu = int128(ONE).div(mu);
        int128 rightSide = invMu.mul(int128(subtotalRaised));

        require(
            rightSide <= int128(sharesReserves),
            "YieldMath: Exchange rate underflow before trade"
        );

        result = sharesReserves - uint128(rightSide);
    }

    /**
     * Calculate the amount of fyToken a user could sell for given amount of Shares.
     * https://www.desmos.com/calculator/5sbqbquaxq
     * @param sharesReserves shares reserves amount
     * @param fyTokenReserves fyToken reserves amount
     * @param sharesAmount Shares amount to be traded
     * @param timeTillMaturity time till maturity in seconds
     * @param k time till maturity coefficient, multiplied by 2^64
     * @param g fee coefficient, multiplied by 2^64
     * @param c price of shares in terms of Dai, multiplied by 2^64
     * @param mu (μ) Normalization factor -- starts as c at initialization
     * @return fyTokenIn the amount of fyToken a user could sell for given amount of Shares
     *
     *      (                  sum                                )
     *        (    Za        )   ( Ya  )   (      Zxa           )   (   invA   )
     * dy = ( c/μ * (μz)^(1-t) + y^(1-t) - c/μ * (μz - μx)^(1-t) )^(1 / (1 - t)) - y
     *
     */
    function fyTokenInForSharesOut(
        uint128 sharesReserves,
        uint128 fyTokenReserves,
        uint128 sharesAmount,
        uint128 timeTillMaturity,
        int128 k,
        int128 g,
        int128 c,
        int128 mu
    ) public pure returns (uint128 fyTokenIn) {
        unchecked {
            require(c > 0, "YieldMath: c must be positive");

            return
                _fyTokenInForSharesOut(
                    sharesReserves,
                    fyTokenReserves,
                    sharesAmount,
                    _computeA(timeTillMaturity, k, g),
                    c,
                    mu
                );
        }
    }

    function _fyTokenInForSharesOut(
        uint128 sharesReserves,
        uint128 fyTokenReserves,
        uint128 sharesAmount,
        uint128 a,
        int128 c,
        int128 mu
    ) public pure returns (uint128 fyTokenIn) {
        // normalizedSharesReserves = μ * sharesReserves
        uint256 normalizedSharesReserves = mu.mulu(sharesReserves);
        require(
            normalizedSharesReserves <= MAX,
            "YieldMath: Exchange rate overflow before trade"
        );

        // za = c/μ * (normalizedSharesReserves ** a)
        uint256 za = c.div(mu).mulu(
            uint128(normalizedSharesReserves).pow(a, ONE)
        );
        require(za <= MAX, "YieldMath: Exchange rate overflow before trade");

        // ya = fyTokenReserves ** a
        uint256 ya = fyTokenReserves.pow(a, ONE);

        // normalizedSharesAmount = μ * sharesAmount
        uint256 normalizedSharesAmount = mu.mulu(sharesAmount);
        require(
            normalizedSharesAmount <= MAX,
            "YieldMath: Exchange rate overflow before trade"
        );

        // zx = normalizedBaseReserves + sharesAmount * μ
        uint256 zx = normalizedSharesReserves - normalizedSharesAmount;
        require(zx <= MAX, "YieldMath: Too much shares in");

        // zxa = c/μ * zx ** a
        uint256 zxa = c.div(mu).mulu(uint128(zx).pow(a, ONE));
        require(zxa <= MAX, "YieldMath: Exchange rate overflow after trade");

        // sum = za + ya - zxa
        uint256 sum = za + ya - zxa; // z < MAX, y < MAX, a < 1. It can only underflow, not overflow.
        require(sum <= MAX, "YieldMath: Insufficient fyToken reserves");

        // result = fyTokenReserves - (sum ** (1/a))
        uint256 result = uint256(uint128(sum).pow(ONE, a)) -
            uint256(fyTokenReserves);
        require(result <= MAX, "YieldMath: Rounding induced error");

        result = result > 1e12 ? result - 1e12 : 0; // Subtract error guard, flooring the result at zero

        return uint128(result);
    }

    /**
     * Calculate the amount of shares a user would have to pay for certain amount of fyToken.
     * https://www.desmos.com/calculator/pfh1eudqa1
     * @param sharesReserves yield bearing vault shares reserve amount
     * @param fyTokenReserves fyToken reserves amount
     * @param fyTokenAmount fyToken amount to be traded
     * @param timeTillMaturity time till maturity in seconds e.g. 90 days in seconds
     * @param k time till maturity coefficient, multiplied by 2^64.  e.g. 25 years in seconds
     * @param g fee coefficient, multiplied by 2^64 -- sb under 1.0 for selling shares to pool
     * @param c price of shares in terms of their base, multiplied by 2^64
     * @param mu (μ) Normalization factor -- starts as c at initialization
     * @return the amount of shares a user would have to pay for given amount of fyToken
     *
     * y = fyToken
     * z = vyToken
     * x = Δy
     *
     *            (                 subtotal                             )
     *              (     Za       )  (  Ya  )   (    Yxa     )             (   invA   )
     * dz = 1/μ * ( ( c/μ * μz^(1-t) + y^(1-t) - (y - x)^(1-t) ) / (c/μ) )^(1 / (1 - t)) - z
     *
     */
    function sharesInForFyTokenOut(
        uint128 sharesReserves,
        uint128 fyTokenReserves,
        uint128 fyTokenAmount,
        uint128 timeTillMaturity,
        int128 k,
        int128 g,
        int128 c,
        int128 mu
    ) public pure returns (uint128) {
        unchecked {
            require(c > 0, "YieldMath: c must be positive");

            return
                _sharesInForFyTokenOut(
                    sharesReserves,
                    fyTokenReserves,
                    fyTokenAmount,
                    _computeA(timeTillMaturity, k, g),
                    c,
                    mu
                );
        }
    }

    /// @dev Splitting sharesInForFyTokenOut in two functions to avoid stack depth limits
    function _sharesInForFyTokenOut(
        uint128 sharesReserves,
        uint128 fyTokenReserves,
        uint128 fyTokenAmount,
        uint128 a,
        int128 c,
        int128 mu
    ) private pure returns (uint128) {
        // normalizedSharesReserves = μ * sharesReserves
        uint256 normalizedSharesReserves = mu.mulu(sharesReserves);
        require(
            normalizedSharesReserves <= MAX,
            "YieldMath: Exchange rate overflow before trade"
        );

        // za = c/μ * (normalizedSharesReserves ** a)
        uint256 za = c.div(mu).mulu(
            uint128(normalizedSharesReserves).pow(a, ONE)
        );
        require(za <= MAX, "YieldMath: Exchange rate overflow before trade");

        // ya = fyTokenReserves ** a
        uint256 ya = fyTokenReserves.pow(a, ONE);

        // yxa = (fyTokenReserves - x) ** a   # x is aka Δy
        uint256 yxa = (fyTokenReserves - fyTokenAmount).pow(a, ONE);

        uint256 subtotalLeft = (za + ya - yxa);
        require(
            subtotalLeft <= MAX,
            "YieldMath: Exchange rate overflow before trade"
        );

        int128 subtotal = subtotalLeft.divu(uint128(c.div(mu)));
        uint128 subtotalRaised = uint128(subtotal).pow(
            uint128(ONE),
            uint128(a)
        );
        int128 invMu = int128(ONE).div(mu);
        int128 leftSide = invMu.mul(int128(subtotalRaised));

        require(
            leftSide >= int128(sharesReserves),
            "YieldMath: Exchange rate underflow before trade"
        );

        return uint128(leftSide) - sharesReserves;
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
     * Calculate the amount of fyToken a user would get for given amount of Shares.
     * A normalization parameter is taken to normalize the exchange rate at a certain value.
     * This is used for liquidity pools to be initialized with balanced reserves.
     * @param sharesReserves shares reserves amount
     * @param fyTokenReserves fyToken reserves amount
     * @param sharesAmount Shares amount to be traded
     * @param timeTillMaturity time till maturity in seconds
     * @param k time till maturity coefficient, multiplied by 2^64
     * @param g fee coefficient, multiplied by 2^64
     * @param c0 price of shares in terms of shares as it was at protocol
     *        initialization time, multiplied by 2^64
     * @param c price of shares in terms of Dai, multiplied by 2^64
     * @param mu (μ) starts as c at initialization
     * @return fyTokenOut the amount of fyToken a user would get for given amount of Shares
     */
    function fyTokenOutForSharesInNormalized(
        uint128 sharesReserves,
        uint128 fyTokenReserves,
        uint128 sharesAmount,
        uint128 timeTillMaturity,
        int128 k,
        int128 g,
        int128 c0,
        int128 c,
        int128 mu
    ) external pure returns (uint128 fyTokenOut) {
        unchecked {
            uint256 normalizedSharesReserves = c0.mulu(sharesReserves);
            require(
                normalizedSharesReserves <= MAX,
                "YieldMath: Overflow on reserve normalization"
            );

            uint256 normalizedSharesAmount = c0.mulu(sharesAmount);
            require(
                normalizedSharesAmount <= MAX,
                "YieldMath: Overflow on trade normalization"
            );

            fyTokenOut = fyTokenOutForSharesIn(
                uint128(normalizedSharesReserves),
                fyTokenReserves,
                uint128(normalizedSharesAmount),
                timeTillMaturity,
                k,
                g,
                c.div(c0),
                mu
            );
        }
    }

    // /**
    //  * Calculate the amount of shares a user would get for certain amount of fyToken.
    //  * A normalization parameter is taken to normalize the exchange rate at a certain value.
    //  * This is used for liquidity pools to be initialized with balanced reserves.
    //  * @param sharesReserves shares reserves amount
    //  * @param fyTokenReserves fyToken reserves amount
    //  * @param fyTokenAmount fyToken amount to be traded
    //  * @param timeTillMaturity time till maturity in seconds
    //  * @param k time till maturity coefficient, multiplied by 2^64
    //  * @param g fee coefficient, multiplied by 2^64
    //  * @param c0 price of shares in terms of Dai as it was at protocol
    //  *        initialization time, multiplied by 2^64
    //  * @param c price of shares in terms of Dai, multiplied by 2^64
    //  * @return sharesOut the amount of shares a user would get for given amount of fyToken
    //  */
    // function sharesOutForFyTokenInNormalized(
    //     uint128 sharesReserves,
    //     uint128 fyTokenReserves,
    //     uint128 fyTokenAmount,
    //     uint128 timeTillMaturity,
    //     int128 k,
    //     int128 g,
    //     int128 c0,
    //     int128 c
    // ) external pure returns (uint128 sharesOut) {
    //     unchecked {
    //         uint256 normalizedSharesReserves = c0.mulu(sharesReserves);
    //         require(
    //             normalizedSharesReserves <= MAX,
    //             "YieldMath: Overflow on reserve normalization"
    //         );

    //         uint256 result = c0.inv().mulu(
    //             sharesOutForFyTokenIn(
    //                 uint128(normalizedSharesReserves),
    //                 fyTokenReserves,
    //                 fyTokenAmount,
    //                 timeTillMaturity,
    //                 k,
    //                 g,
    //                 c.div(c0)
    //             )
    //         );
    //         require(
    //             result <= MAX,
    //             "YieldMath: Overflow on result normalization"
    //         );

    //         sharesOut = uint128(result);
    //     }
    // }

    // /**
    //  * Calculate the amount of fyToken a user could sell for given amount of Shares.
    //  *
    //  * @param sharesReserves shares reserves amount
    //  * @param fyTokenReserves fyToken reserves amount
    //  * @param sharesAmount shares amount to be traded
    //  * @param timeTillMaturity time till maturity in seconds
    //  * @param k time till maturity coefficient, multiplied by 2^64
    //  * @param g fee coefficient, multiplied by 2^64
    //  * @param c0 price of shares in terms of Dai as it was at protocol
    //  *        initialization time, multiplied by 2^64
    //  * @param c price of shares in terms of Dai, multiplied by 2^64
    //  * @return fyTokenIn the amount of fyToken a user could sell for given amount of Shares
    //  */
    // function fyTokenInForSharesOutNormalized(
    //     uint128 sharesReserves,
    //     uint128 fyTokenReserves,
    //     uint128 sharesAmount,
    //     uint128 timeTillMaturity,
    //     int128 k,
    //     int128 g,
    //     int128 c0,
    //     int128 c
    // ) external pure returns (uint128 fyTokenIn) {
    //     unchecked {
    //         uint256 normalizedSharesReserves = c0.mulu(sharesReserves);
    //         require(
    //             normalizedSharesReserves <= MAX,
    //             "YieldMath: Overflow on reserve normalization"
    //         );

    //         uint256 normalizedSharesAmount = c0.mulu(sharesAmount);
    //         require(
    //             normalizedSharesAmount <= MAX,
    //             "YieldMath: Overflow on trade normalization"
    //         );

    //         fyTokenIn = fyTokenInForSharesOut(
    //             uint128(normalizedSharesReserves),
    //             fyTokenReserves,
    //             uint128(normalizedSharesAmount),
    //             timeTillMaturity,
    //             k,
    //             g,
    //             c.div(c0)
    //         );
    //     }
    // }

    // /**
    //  * Calculate the amount of Shares a user would have to pay for certain amount of
    //  * fyToken.
    //  *
    //  * @param sharesReserves shares reserves amount
    //  * @param fyTokenReserves fyToken reserves amount
    //  * @param fyTokenAmount fyToken amount to be traded
    //  * @param timeTillMaturity time till maturity in seconds
    //  * @param k time till maturity coefficient, multiplied by 2^64
    //  * @param g fee coefficient, multiplied by 2^64
    //  * @param c0 price of shares in terms of Shares as it was at protocol
    //  *        initialization time, multiplied by 2^64
    //  * @param c price of shares in terms of Dai, multiplied by 2^64
    //  * @return sharesIn the amount of shares a user would have to pay for given amount of fyToken
    //  */
    // function sharesInForFyTokenOutNormalized(
    //     uint128 sharesReserves,
    //     uint128 fyTokenReserves,
    //     uint128 fyTokenAmount,
    //     uint128 timeTillMaturity,
    //     int128 k,
    //     int128 g,
    //     int128 c0,
    //     int128 c
    // ) external pure returns (uint128 sharesIn) {
    //     unchecked {
    //         uint256 normalizedSharesReserves = c0.mulu(sharesReserves);
    //         require(
    //             normalizedSharesReserves <= MAX,
    //             "YieldMath: Overflow on reserve normalization"
    //         );

    //         uint256 result = c0.inv().mulu(
    //             sharesInForFyTokenOut(
    //                 uint128(normalizedSharesReserves),
    //                 fyTokenReserves,
    //                 fyTokenAmount,
    //                 timeTillMaturity,
    //                 k,
    //                 g,
    //                 c.div(c0)
    //             )
    //         );
    //         require(
    //             result <= MAX,
    //             "YieldMath: Overflow on result normalization"
    //         );

    //         sharesIn = uint128(result);
    //     }
    // }

    /**
     * Estimate in Shares the value of reserves at protocol initialization time.
     *
     * @param sharesReserves shares reserves amount
     * @param fyTokenReserves fyToken reserves amount
     * @param timeTillMaturity time till maturity in seconds
     * @param k time till maturity coefficient, multiplied by 2^64
     * @param c0 price of shares in terms of Dai, multiplied by 2^64
     * @return initialReserves estimated value of reserves
     */
    // function initialReservesValue(
    //     uint128 sharesReserves,
    //     uint128 fyTokenReserves,
    //     uint128 timeTillMaturity,
    //     int128 k,
    //     int128 c0
    // ) external pure returns (uint128 initialReserves) {
    //     unchecked {
    //         uint256 normalizedSharesReserves = c0.mulu(sharesReserves);
    //         require(normalizedSharesReserves <= MAX);

    //         // a = (1 - k * timeTillMaturity)
    //         int128 a = int128(ONE).sub(k.mul(timeTillMaturity.fromUInt()));
    //         require(a > 0);

    //         uint256 sum = (uint256(
    //             uint128(normalizedSharesReserves).pow(uint128(a), ONE)
    //         ) + uint256(fyTokenReserves.pow(uint128(a), ONE))) >> 1;
    //         require(sum <= MAX);

    //         uint256 result = uint256(uint128(sum).pow(ONE, uint128(a))) << 1;
    //         require(result <= MAX);

    //         initialReserves = uint128(result);
    //     }
    // }
    /**
     * Calculate the amount of shares a user would have to pay for certain amount of fyToken.
     * https://www.desmos.com/calculator/ws5oqj8x5i
     * @param sharesReserves Shares reserves amount
     * @param fyTokenReserves fyToken reserves amount
     * @param fyTokenAmount fyToken amount to be traded
     * @param timeTillMaturity time till maturity in seconds
     * @param k time till maturity coefficient, multiplied by 2^64
     * @param g fee coefficient, multiplied by 2^64
     * @param c price of shares in terms of Dai, multiplied by 2^64
     * @return the amount of shares a user would have to pay for given amount of fyToken
     */
    // function old__sharesInForFyTokenOut(
    //     uint128 sharesReserves,
    //     uint128 fyTokenReserves,
    //     uint128 fyTokenAmount,
    //     uint128 timeTillMaturity,
    //     int128 k,
    //     int128 g,
    //     int128 c
    // ) public pure returns (uint128) {
    //     unchecked {
    //         require(c > 0, "YieldMath: c must be positive");

    //         return
    //             _sharesInForFyTokenOut(
    //                 sharesReserves,
    //                 fyTokenReserves,
    //                 fyTokenAmount,
    //                 _computeA(timeTillMaturity, k, g),
    //                 c
    //             );
    //     }
    // }

    // /// @dev Splitting sharesInForFyTokenOut in two functions to avoid stack depth limits.
    // function old_sharesInForFyTokenOut(
    //     uint128 sharesReserves,
    //     uint128 fyTokenReserves,
    //     uint128 fyTokenAmount,
    //     uint128 a,
    //     int128 c
    // ) private pure returns (uint128) {
    //     unchecked {
    //         // invC = 1 / c
    //         int128 invC = c.inv();

    //         // za = c * (sharesReserves ** a)
    //         uint256 za = c.mulu(sharesReserves.pow(a, ONE));
    //         require(
    //             za <= MAX,
    //             "YieldMath: Exchange rate overflow before trade"
    //         );

    //         // ya = fyTokenReserves ** a
    //         uint256 ya = fyTokenReserves.pow(a, ONE);

    //         // yx = sharesReserves - sharesAmount
    //         uint256 yx = uint256(fyTokenReserves) - uint256(fyTokenAmount);
    //         require(yx <= MAX, "YieldMath: Too much fyToken out");

    //         // yxa = yx ** a
    //         uint256 yxa = uint128(yx).pow(a, ONE);

    //         // sum = za + ya - yxa
    //         uint256 sum = za + ya - yxa; // z < MAX, y < MAX, a < 1. It can only underflow, not overflow.
    //         require(
    //             sum <= MAX,
    //             "YieldMath: Resulting shares reserves too high"
    //         );

    //         // (1/c) * sum
    //         uint256 invCsum = invC.mulu(sum);
    //         require(invCsum <= MAX, "YieldMath: c too close to zero");

    //         // result = (((1/c) * sum) ** (1/a)) - sharesReserves
    //         uint256 result = uint256(uint128(invCsum).pow(ONE, a)) -
    //             uint256(sharesReserves);
    //         require(result <= MAX, "YieldMath: Rounding induced error");

    //         result = result < MAX - 1e12 ? result + 1e12 : MAX; // Add error guard, ceiling the result at max

    //         return uint128(result);
    //     }
    // }
}
