// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.13;

import {Math64x64} from "./Math64x64.sol";
import {Exp64x64} from "./Exp64x64.sol";

/*
   __     ___      _     _
   \ \   / (_)    | |   | | ██╗   ██╗██╗███████╗██╗     ██████╗ ███╗   ███╗ █████╗ ████████╗██╗  ██╗
    \ \_/ / _  ___| | __| | ╚██╗ ██╔╝██║██╔════╝██║     ██╔══██╗████╗ ████║██╔══██╗╚══██╔══╝██║  ██║
     \   / | |/ _ \ |/ _` |  ╚████╔╝ ██║█████╗  ██║     ██║  ██║██╔████╔██║███████║   ██║   ███████║
      | |  | |  __/ | (_| |   ╚██╔╝  ██║██╔══╝  ██║     ██║  ██║██║╚██╔╝██║██╔══██║   ██║   ██╔══██║
      |_|  |_|\___|_|\__,_|    ██║   ██║███████╗███████╗██████╔╝██║ ╚═╝ ██║██║  ██║   ██║   ██║  ██║
       yieldprotocol.com       ╚═╝   ╚═╝╚══════╝╚══════╝╚═════╝ ╚═╝     ╚═╝╚═╝  ╚═╝   ╚═╝   ╚═╝  ╚═╝
*/
/// Ethereum smart contract library implementing Yield Math model with yield bearing tokens.
library YieldMath {
    using Math64x64 for int128;
    using Math64x64 for uint128;
    using Math64x64 for int256;
    using Math64x64 for uint256;
    using Exp64x64 for uint128;

    uint128 public constant ONE = 0x10000000000000000; //   In 64.64
    uint256 public constant MAX = type(uint128).max; //     Used for overflow checks


    /* CORE FUNCTIONS
    ******************************************************************************************************************/

    /* ----------------------------------------------------------------------------------------------------------------
                                              ┌───────────────────────────────┐                    .-:::::::::::-.
      ┌──────────────┐                        │                               │                  .:::::::::::::::::.
      │$            $│                       \│                               │/                :  _______  __   __ :
      │ ┌────────────┴─┐                     \│                               │/               :: |       ||  | |  |::
      │ │$            $│                      │    fyTokenOutForSharesIn      │               ::: |    ___||  |_|  |:::
      │$│ ┌────────────┴─┐     ────────▶      │                               │  ────────▶    ::: |   |___ |       |:::
      └─┤ │$            $│                    │                               │               ::: |    ___||_     _|:::
        │$│  `sharesIn`  │                   /│                               │\              ::: |   |      |   |  :::
        └─┤              │                   /│                               │\               :: |___|      |___|  ::
          │$            $│                    │                      \(^o^)/  │                 :       ????        :
          └──────────────┘                    │                     YieldMath │                  `:::::::::::::::::'
                                              └───────────────────────────────┘                    `-:::::::::::-'
    */
    /// Calculates the amount of fyToken a user would get for given amount of shares.
    /// https://docs.google.com/spreadsheets/d/14K_McZhlgSXQfi6nFGwDvDh4BmOu6_Hczi_sFreFfOE/
    /// @param sharesReserves yield bearing vault shares reserve amount
    /// @param fyTokenReserves fyToken reserves amount
    /// @param sharesIn shares amount to be traded
    /// @param timeTillMaturity time till maturity in seconds e.g. 90 days in seconds
    /// @param k time till maturity coefficient, multiplied by 2^64.  e.g. 25 years in seconds
    /// @param g fee coefficient, multiplied by 2^64 -- sb under 1.0 for selling shares to pool
    /// @param c price of shares in terms of their base, multiplied by 2^64
    /// @param mu (μ) Normalization factor -- starts as c at initialization
    /// @return fyTokenOut the amount of fyToken a user would get for given amount of shares
    function fyTokenOutForSharesIn(
        uint128 sharesReserves, // z
        uint128 fyTokenReserves, // x
        uint128 sharesIn, // dx
        uint128 timeTillMaturity,
        int128 k,
        int128 g,
        int128 c,
        int128 mu
    ) public pure returns (uint128 fyTokenOut) {
        // TODO: If we stick w 0.8.13 then consider removing the internal fn for this and others
        unchecked {
            require(c > 0 && mu > 0, "YieldMath: c and mu must be positive");

            return
                _fyTokenOutForSharesIn(
                    sharesReserves,
                    fyTokenReserves,
                    sharesIn,
                    _computeA(timeTillMaturity, k, g),
                    c,
                    mu
                );
        }
    }

    function _fyTokenOutForSharesIn(
        uint128 sharesReserves, // z
        uint128 fyTokenReserves, // x
        uint128 sharesIn, // dx
        uint128 a,
        int128 c,
        int128 mu
    ) internal pure returns (uint128) {
        /* https://docs.google.com/spreadsheets/d/14K_McZhlgSXQfi6nFGwDvDh4BmOu6_Hczi_sFreFfOE/

                    (                        sum                          )
                    (    Za        )   ( Ya  )   (       Zxa         )   (   invA   )
        dy = y - ( c/μ * (μz)^(1-t) + y^(1-t) - c/μ * (μz + μdx)^(1-t) )^(1 / (1 - t))

        */
        // normalizedSharesReserves = μ * sharesReserves
        uint256 normalizedSharesReserves = mu.mulu(sharesReserves);
        require(normalizedSharesReserves <= MAX, "YieldMath: Exchange rate overflow before trade");

        // za = c/μ * (normalizedSharesReserves ** a)
        uint256 za = c.div(mu).mulu(uint128(normalizedSharesReserves).pow(a, ONE));
        require(za <= MAX, "YieldMath: Exchange rate overflow before trade");

        // ya = fyTokenReserves ** a
        uint256 ya = fyTokenReserves.pow(a, ONE);

        // normalizedSharesIn = μ * sharesIn
        uint256 normalizedSharesIn = mu.mulu(sharesIn);
        require(normalizedSharesIn <= MAX, "YieldMath: Exchange rate overflow before trade");

        // zx = normalizedBaseReserves + sharesIn * μ
        uint256 zx = normalizedSharesReserves + normalizedSharesIn;
        require(zx <= MAX, "YieldMath: Too much shares in");

        // zxa = c/μ * zx ** a
        uint256 zxa = c.div(mu).mulu(uint128(zx).pow(a, ONE));
        require(zxa <= MAX, "YieldMath: Exchange rate overflow after trade");

        // sum = za + ya - zxa
        uint256 sum = za + ya - zxa; // z < MAX, y < MAX, a < 1. It can only underflow, not overflow.
        require(sum <= MAX, "YieldMath: Insufficient fyToken reserves");

        // result = fyTokenReserves - (sum ** (1/a))
        uint256 result = uint256(fyTokenReserves) - uint256(uint128(sum).pow(ONE, a));
        require(result <= MAX, "YieldMath: Rounding induced error");

        result = result < MAX - 1e12 ? result + 1e12 : MAX; // Add error guard, ceiling the result at max

        return uint128(result);
    }

    /* ----------------------------------------------------------------------------------------------------------------
          .-:::::::::::-.                       ┌───────────────────────────────┐
        .:::::::::::::::::.                     │                               │
       :  _______  __   __ :                   \│                               │/              ┌──────────────┐
      :: |       ||  | |  |::                  \│                               │/              │$            $│
     ::: |    ___||  |_|  |:::                  │    sharesOutForFYTokenIn      │               │ ┌────────────┴─┐
     ::: |   |___ |       |:::   ────────▶      │                               │  ────────▶    │ │$            $│
     ::: |    ___||_     _|:::                  │                               │               │$│ ┌────────────┴─┐
     ::: |   |      |   |  :::                 /│                               │\              └─┤ │$            $│
      :: |___|      |___|  ::                  /│                               │\                │$│    SHARES    │
       :     `fyTokenIn`   :                    │                      \(^o^)/  │                 └─┤     ????     │
        `:::::::::::::::::'                     │                     YieldMath │                   │$            $│
          `-:::::::::::-'                       └───────────────────────────────┘                   └──────────────┘
    */
    /// Calculates the amount of shares a user would get for certain amount of fyToken.
    /// @param sharesReserves shares reserves amount
    /// @param fyTokenReserves fyToken reserves amount
    /// @param fyTokenIn fyToken amount to be traded
    /// @param timeTillMaturity time till maturity in seconds
    /// @param k time till maturity coefficient, multiplied by 2^64
    /// @param g fee coefficient, multiplied by 2^64
    /// @param c price of shares in terms of Dai, multiplied by 2^64
    /// @param mu (μ) Normalization factor -- starts as c at initialization
    /// @return the amount of Shares a user would get for given amount of fyToken
    function sharesOutForFYTokenIn(
        uint128 sharesReserves,
        uint128 fyTokenReserves,
        uint128 fyTokenIn,
        uint128 timeTillMaturity,
        int128 k,
        int128 g,
        int128 c,
        int128 mu
    ) public pure returns (uint128) {
        unchecked {
            require(c > 0, "YieldMath: c must be positive");

            return
                _sharesOutForFYTokenIn(
                    sharesReserves,
                    fyTokenReserves,
                    fyTokenIn,
                    _computeA(timeTillMaturity, k, g),
                    c,
                    mu
                );
        }
    }

    /// @dev Splitting sharesOutForFYTokenIn in two functions to avoid stack depth limits.
    function _sharesOutForFYTokenIn(
        uint128 sharesReserves,
        uint128 fyTokenReserves,
        uint128 fyTokenIn,
        uint128 a,
        int128 c,
        int128 mu
    ) private pure returns (uint128 result) {
        /* https://docs.google.com/spreadsheets/d/14K_McZhlgSXQfi6nFGwDvDh4BmOu6_Hczi_sFreFfOE/

                          (                     sum                                       )
                            (       Za           )   ( Ya  )    (    Yxa     )              (   invA    )
          dz = z - 1/μ  * ( ( (c / μ) * (μz)^(1-t) + y^(1-t) -  (y + x)^(1-t) ) / (c / μ) )^(1 / (1 - t))

        */
        // normalizedSharesReserves = μ * sharesReserves
        uint256 normalizedSharesReserves = mu.mulu(sharesReserves);
        require(normalizedSharesReserves <= MAX, "YieldMath: Exchange rate overflow before trade");
        uint256 subtotalLeft = _getSubtotalLeft(normalizedSharesReserves, fyTokenReserves, fyTokenIn, a, c, mu);
        require(subtotalLeft <= MAX, "YieldMath: Exchange rate overflow before trade");

        int128 subtotal = subtotalLeft.divu(uint128(c.div(mu)));
        uint128 subtotalRaised = uint128(subtotal).pow(uint128(ONE), uint128(a));
        int128 invMu = int128(ONE).div(mu);
        int128 rightSide = invMu.mul(int128(subtotalRaised));

        require(rightSide <= int128(sharesReserves), "YieldMath: Exchange rate underflow before trade");

        result = sharesReserves - uint128(rightSide);
    }

    function _getSubtotalLeft(
        uint256 normalizedSharesReserves,
        uint128 fyTokenReserves,
        uint128 fyTokenIn,
        uint128 a,
        int128 c,
        int128 mu
    ) internal pure returns (uint256 subtotalLeft) {
        // za = c/μ * (normalizedSharesReserves ** a)
        uint256 za = c.div(mu).mulu(uint128(normalizedSharesReserves).pow(a, ONE));
        require(za <= MAX, "YieldMath: Exchange rate overflow before trade");

        // ya = fyTokenReserves ** a
        uint256 ya = fyTokenReserves.pow(a, ONE);

        // yxa = (fyTokenReserves + x) ** a   # x is aka Δy
        uint256 yxa = (fyTokenReserves + fyTokenIn).pow(a, ONE);

        subtotalLeft = (za + ya - yxa);
    }

    /* ----------------------------------------------------------------------------------------------------------------
          .-:::::::::::-.                       ┌───────────────────────────────┐
        .:::::::::::::::::.                     │                               │              ┌──────────────┐
       :  _______  __   __ :                   \│                               │/             │$            $│
      :: |       ||  | |  |::                  \│                               │/             │ ┌────────────┴─┐
     ::: |    ___||  |_|  |:::                  │    fyTokenInForSharesOut      │              │ │$            $│
     ::: |   |___ |       |:::   ────────▶      │                               │  ────────▶   │$│ ┌────────────┴─┐
     ::: |    ___||_     _|:::                  │                               │              └─┤ │$            $│
     ::: |   |      |   |  :::                 /│                               │\               │$│              │
      :: |___|      |___|  ::                  /│                               │\               └─┤  `sharesOut` │
       :        ????       :                    │                      \(^o^)/  │                  │$            $│
        `:::::::::::::::::'                     │                     YieldMath │                  └──────────────┘
          `-:::::::::::-'                       └───────────────────────────────┘
    */
    /// Calculates the amount of fyToken a user could sell for given amount of Shares.
    /// @param sharesReserves shares reserves amount
    /// @param fyTokenReserves fyToken reserves amount
    /// @param sharesOut Shares amount to be traded
    /// @param timeTillMaturity time till maturity in seconds
    /// @param k time till maturity coefficient, multiplied by 2^64
    /// @param g fee coefficient, multiplied by 2^64
    /// @param c price of shares in terms of Dai, multiplied by 2^64
    /// @param mu (μ) Normalization factor -- starts as c at initialization
    /// @return fyTokenIn the amount of fyToken a user could sell for given amount of Shares
    function fyTokenInForSharesOut(
        uint128 sharesReserves,
        uint128 fyTokenReserves,
        uint128 sharesOut,
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
                    sharesOut,
                    _computeA(timeTillMaturity, k, g),
                    c,
                    mu
                );
        }
    }

    function _fyTokenInForSharesOut(
        uint128 sharesReserves,
        uint128 fyTokenReserves,
        uint128 sharesOut,
        uint128 a,
        int128 c,
        int128 mu
    ) public pure returns (uint128 fyTokenIn) {
        /* https://docs.google.com/spreadsheets/d/14K_McZhlgSXQfi6nFGwDvDh4BmOu6_Hczi_sFreFfOE/

               (                  sum                               )
                 (    Za        ) + ( Ya  ) - (       Zxa           )^(   invA    )
          dy = ( c/μ * (μz)^(1-t) + y^(1-t) - c/μ * (μz - μx)^(1-t) )^(1 / (1 - t)) - y

        */
        // normalizedSharesReserves = μ * sharesReserves
        uint256 normalizedSharesReserves = mu.mulu(sharesReserves);
        require(normalizedSharesReserves <= MAX, "YieldMath: Exchange rate overflow before trade");

        // za = c/μ * (normalizedSharesReserves ** a)
        uint256 za = c.div(mu).mulu(uint128(normalizedSharesReserves).pow(a, ONE));
        require(za <= MAX, "YieldMath: Exchange rate overflow before trade");

        // ya = fyTokenReserves ** a
        uint256 ya = fyTokenReserves.pow(a, ONE);

        // normalizedSharesOut = μ * sharesOut
        uint256 normalizedSharesOut = mu.mulu(sharesOut);
        require(normalizedSharesOut <= MAX, "YieldMath: Exchange rate overflow before trade");

        // zx = normalizedBaseReserves + sharesOut * μ
        require(normalizedSharesReserves >= normalizedSharesOut, "YieldMath: Too much shares in");
        uint256 zx = normalizedSharesReserves - normalizedSharesOut;

        // zxa = c/μ * zx ** a
        uint256 zxa = c.div(mu).mulu(uint128(zx).pow(a, ONE));
        require(zxa <= MAX, "YieldMath: Exchange rate overflow after trade");

        // sum = za + ya - zxa
        uint256 sum = za + ya - zxa; // z < MAX, y < MAX, a < 1. It can only underflow, not overflow.
        require(sum <= MAX, "YieldMath: Insufficient fyToken reserves");

        // result = fyTokenReserves - (sum ** (1/a))
        uint256 result = uint256(uint128(sum).pow(ONE, a)) - uint256(fyTokenReserves);
        require(result <= MAX, "YieldMath: Rounding induced error");

        result = result > 1e12 ? result - 1e12 : 0; // Subtract error guard, flooring the result at zero

        return uint128(result);
    }

    /* ----------------------------------------------------------------------------------------------------------------
                                              ┌───────────────────────────────┐                    .-:::::::::::-.
      ┌──────────────┐                        │                               │                  .:::::::::::::::::.
      │$            $│                       \│                               │/                :  _______  __   __ :
      │ ┌────────────┴─┐                     \│                               │/               :: |       ||  | |  |::
      │ │$            $│                      │    sharesInForFYTokenOut      │               ::: |    ___||  |_|  |:::
      │$│ ┌────────────┴─┐     ────────▶      │                               │  ────────▶    ::: |   |___ |       |:::
      └─┤ │$            $│                    │                               │               ::: |    ___||_     _|:::
        │$│    SHARES    │                   /│                               │\              ::: |   |      |   |  :::
        └─┤     ????     │                   /│                               │\               :: |___|      |___|  ::
          │$            $│                    │                      \(^o^)/  │                 :   `fyTokenOut`    :
          └──────────────┘                    │                     YieldMath │                  `:::::::::::::::::'
                                              └───────────────────────────────┘                    `-:::::::::::-'
    */
    /// @param sharesReserves yield bearing vault shares reserve amount
    /// @param fyTokenReserves fyToken reserves amount
    /// @param fyTokenAmount fyToken amount to be traded
    /// @param timeTillMaturity time till maturity in seconds e.g. 90 days in seconds
    /// @param k time till maturity coefficient, multiplied by 2^64.  e.g. 25 years in seconds
    /// @param g fee coefficient, multiplied by 2^64 -- sb under 1.0 for selling shares to pool
    /// @param c price of shares in terms of their base, multiplied by 2^64
    /// @param mu (μ) Normalization factor -- starts as c at initialization
    /// @return the amount of shares a user would have to pay for given amount of fyToken
    function sharesInForFYTokenOut(
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
                _sharesInForFYTokenOut(
                    sharesReserves,
                    fyTokenReserves,
                    fyTokenAmount,
                    _computeA(timeTillMaturity, k, g),
                    c,
                    mu
                );
        }
    }

    /// @dev Splitting sharesInForFYTokenOut in two functions to avoid stack depth limits
    function _sharesInForFYTokenOut(
        uint128 sharesReserves,
        uint128 fyTokenReserves,
        uint128 fyTokenAmount,
        uint128 a,
        int128 c,
        int128 mu
    ) private pure returns (uint128) {
        /* https://docs.google.com/spreadsheets/d/14K_McZhlgSXQfi6nFGwDvDh4BmOu6_Hczi_sFreFfOE/

            y = fyToken
            z = vyToken
            x = Δy

                        (                 subtotal                             )
                        (     Za       )  (  Ya  )   (    Yxa     )             (   invA   )
            dz = 1/μ * ( ( c/μ * μz^(1-t) + y^(1-t) - (y - x)^(1-t) ) / (c/μ) )^(1 / (1 - t)) - z

        */

        // normalizedSharesReserves = μ * sharesReserves
        uint256 normalizedSharesReserves = mu.mulu(sharesReserves);
        require(normalizedSharesReserves <= MAX, "YieldMath: Exchange rate overflow before trade");

        // za = c/μ * (normalizedSharesReserves ** a)
        uint256 za = c.div(mu).mulu(uint128(normalizedSharesReserves).pow(a, ONE));
        require(za <= MAX, "YieldMath: Exchange rate overflow before trade");

        // ya = fyTokenReserves ** a
        uint256 ya = fyTokenReserves.pow(a, ONE);

        // yxa = (fyTokenReserves - x) ** a   # x is aka Δy
        uint256 yxa = (fyTokenReserves - fyTokenAmount).pow(a, ONE);

        uint256 subtotalLeft = (za + ya - yxa);
        require(subtotalLeft <= MAX, "YieldMath: Exchange rate overflow before trade");

        int128 subtotal = subtotalLeft.divu(uint128(c.div(mu)));
        uint128 subtotalRaised = uint128(subtotal).pow(uint128(ONE), uint128(a));
        int128 invMu = int128(ONE).div(mu);
        int128 leftSide = invMu.mul(int128(subtotalRaised));

        require(leftSide >= int128(sharesReserves), "YieldMath: Exchange rate underflow before trade");

        return uint128(leftSide) - sharesReserves;
    }

    /* MAX FUNCTIONS
    ******************************************************************************************************************/

    /// @notice Calculates the maximum amount of fyToken a user could sell for given amount of Shares.
    /// @param sharesReserves shares reserves amount
    /// @param fyTokenReserves fyToken reserves amount
    /// @param timeTillMaturity time till maturity in seconds
    /// @param k time till maturity coefficient, multiplied by 2^64
    /// @param g fee coefficient, multiplied by 2^64
    /// @param c price of shares in terms of Dai, multiplied by 2^64
    /// @param mu (μ) Normalization factor -- starts as c at initialization
    /// @return fyTokenIn the amount of fyToken a user could sell for given amount of Shares
    function maxFYTokenIn(
        uint128 sharesReserves,
        uint128 fyTokenReserves,
        uint128 timeTillMaturity,
        int128 k, // TODO: Is this ts()??
        int128 g,
        int128 c,
        int128 mu
    ) public pure returns (uint128 fyTokenIn) {
        unchecked {
            require(c > 0, "YieldMath: c must be positive");

            return _maxFYTokenIn(sharesReserves, fyTokenReserves, _computeA(timeTillMaturity, k, g), c, mu);
        }
    }

    function _maxFYTokenIn(
        uint128 sharesReserves,
        uint128 fyTokenReserves,
        uint128 a,
        int128 c,
        int128 mu
    ) public pure returns (uint128 fyTokenIn) {
        /* https://docs.google.com/spreadsheets/d/14K_McZhlgSXQfi6nFGwDvDh4BmOu6_Hczi_sFreFfOE/

                    (                  sum                  )
                    (    Za        )   ( Ya  )   (   invA   )
            dy = ( c/μ * (μz)^(1-t) + y^(1-t) )^(1 / (1 - t)) - y

        */
        // normalizedSharesReserves = μ * sharesReserves
        uint256 normalizedSharesReserves = mu.mulu(sharesReserves);
        require(normalizedSharesReserves <= MAX, "YieldMath: Exchange rate overflow before trade");

        // za = c/μ * (normalizedSharesReserves ** a)
        uint256 za = c.div(mu).mulu(uint128(normalizedSharesReserves).pow(a, ONE));
        require(za <= MAX, "YieldMath: Exchange rate overflow before trade");

        // ya = fyTokenReserves ** a
        uint256 ya = fyTokenReserves.pow(a, ONE);

        // sum = za + ya
        uint256 sum = za + ya; // z < MAX, y < MAX, a < 1. It can only underflow, not overflow.
        require(sum <= MAX, "YieldMath: Insufficient fyToken reserves");

        // result = fyTokenReserves - (sum ** (1/a))
        uint256 result = uint256(uint128(sum).pow(ONE, a)) - uint256(fyTokenReserves);
        require(result <= MAX, "YieldMath: Rounding induced error");

        result = result > 1e12 ? result - 1e12 : 0; // Subtract error guard, flooring the result at zero

        return uint128(result);
    }


    /// @notice Calculates the max amount of fyToken that could go out based on current reserves.
    /// @param sharesReserves yield bearing vault shares reserve amount
    /// @param fyTokenReserves fyToken reserves amount
    /// @param timeTillMaturity time till maturity in seconds e.g. 90 days in seconds
    /// @param k time till maturity coefficient, multiplied by 2^64.  e.g. 25 years in seconds
    /// @param g fee coefficient, multiplied by 2^64 -- sb under 1.0 for selling shares to pool
    /// @param c price of shares in terms of their base, multiplied by 2^64
    /// @param mu (μ) Normalization factor -- starts as c at initialization
    /// @return fyTokenOut the amount of fyToken a user would get for given amount of shares
    function maxFYTokenOut(
        uint128 sharesReserves, // z
        uint128 fyTokenReserves, // x
        uint128 timeTillMaturity,
        int128 k,
        int128 g,
        int128 c,
        int128 mu
    ) public pure returns (uint128 fyTokenOut) {
        unchecked {
            require(c > 0 && mu > 0, "YieldMath: c and mu must be positive");
            return _maxFYTokenOut(sharesReserves, fyTokenReserves, _computeA(timeTillMaturity, k, g), c, mu);
        }
    }

    function _maxFYTokenOut(
        uint128 sharesReserves, // z
        uint128 fyTokenReserves, // y
        uint128 a,
        int128 c,
        int128 mu
    ) internal pure returns (uint128) {
        /* https://docs.google.com/spreadsheets/d/14K_McZhlgSXQfi6nFGwDvDh4BmOu6_Hczi_sFreFfOE/

            dy = y - ((        numerator               ) / (    denominator               ))^(   invA  )
            dy = y - (( cμ^(1-t) * z^(1-t) + μ*y^(1-t) ) / (  c*μ^(1-t) * (1/c)^(1-t) + μ ))^( 1/(1-t) )

        Note: in the above equation t represents g * k * T
                (1-t) is calculated separately in computeA and thereafter referred to as 'a' */

        //                  termA       termB      termC
        // numerator =    cμ^(1-t)  * z^(1-t) +  mu * y^(1-t)
        int128 termA = c.mul(int128(uint128(mu).pow(a, ONE)));
        uint256 termB = sharesReserves.pow(a, ONE);
        uint256 termC = mu.mulu(fyTokenReserves.pow(a, ONE));
        uint256 numerator = termA.mulu(termB) + termC;

        // denominator =  c*μ^(1-t) * (1/c)^(1-t) + μ
        uint256 denominator = uint256(uint128(termA.mul(int128(uint128(int128(ONE).div(c)).pow(a, ONE))) + mu));
        // uint256 denominator = uint256(uint128(c.div(mu)).pow(t, ONE) + ONE);

        int128 result64 = fyTokenReserves.fromUInt() - int128(uint128(numerator / (denominator)).pow(ONE, a));
        // int128 result64 = fyTokenReserves.fromUInt() - int128(uint128(numerator / (denominator)).pow(ONE, a));
        // return result64.toUInt();
    }

    /* UTILITY FUNCTIONS
    ******************************************************************************************************************/

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

}
