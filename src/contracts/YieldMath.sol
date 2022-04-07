// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.13;

/*
   __     ___      _     _
   \ \   / (_)    | |   | | ██╗   ██╗██╗███████╗██╗     ██████╗ ███╗   ███╗ █████╗ ████████╗██╗  ██╗
    \ \_/ / _  ___| | __| | ╚██╗ ██╔╝██║██╔════╝██║     ██╔══██╗████╗ ████║██╔══██╗╚══██╔══╝██║  ██║
     \   / | |/ _ \ |/ _` |  ╚████╔╝ ██║█████╗  ██║     ██║  ██║██╔████╔██║███████║   ██║   ███████║
      | |  | |  __/ | (_| |   ╚██╔╝  ██║██╔══╝  ██║     ██║  ██║██║╚██╔╝██║██╔══██║   ██║   ██╔══██║
      |_|  |_|\___|_|\__,_|    ██║   ██║███████╗███████╗██████╔╝██║ ╚═╝ ██║██║  ██║   ██║   ██║  ██║
       yieldprotocol.com       ╚═╝   ╚═╝╚══════╝╚══════╝╚═════╝ ╚═╝     ╚═╝╚═╝  ╚═╝   ╚═╝   ╚═╝  ╚═╝
*/

import {Math64x64} from "./Math64x64.sol";
import {Exp64x64} from "./Exp64x64.sol";

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
        uint128 sharesIn, // x == Δz
        uint128 timeTillMaturity,
        int128 k,
        int128 g,
        int128 c,
        int128 mu
    ) public pure returns (uint128) {
        unchecked {
            require(c > 0 && mu > 0, "YieldMath: c and mu must be positive");

            uint128 a = _computeA(timeTillMaturity, k, g);

            uint256 sum;
            {
                /* https://docs.google.com/spreadsheets/d/14K_McZhlgSXQfi6nFGwDvDh4BmOu6_Hczi_sFreFfOE/

                y = fyToken reserves
                z = base reserves
                x = Δz (sharesIn)

                     y - (                         sum                           )^(   invA   )
                     y - ((    Za         ) + (  Ya  ) - (       Zxa           ) )^(   invA   )
                Δy = y - ( c/μ * (μz)^(1-t) +  y^(1-t) -  c/μ * (μz + μdx)^(1-t) )^(1 / (1 - t))

                */
                uint256 normalizedSharesReserves;
                require(
                    (normalizedSharesReserves = mu.mulu(sharesReserves)) <= MAX,
                    "YieldMath: Exchange rate overflow before trade"
                );

                // za = c/μ * (normalizedSharesReserves ** a)
                uint256 za;
                require(
                    (za = c.div(mu).mulu(uint128(normalizedSharesReserves).pow(a, ONE))) <= MAX,
                    "YieldMath: Exchange rate overflow before trade"
                );

                // ya = fyTokenReserves ** a
                uint256 ya = fyTokenReserves.pow(a, ONE);

                // normalizedSharesIn = μ * sharesIn
                uint256 normalizedSharesIn;
                require(
                    (normalizedSharesIn = mu.mulu(sharesIn)) <= MAX,
                    "YieldMath: Exchange rate overflow before trade"
                );

                // zx = normalizedBaseReserves + sharesIn * μ
                uint256 zx;
                require((zx = normalizedSharesReserves + normalizedSharesIn) <= MAX, "YieldMath: Too much shares in");

                // zxa = c/μ * zx ** a
                uint256 zxa;
                require(
                    (zxa = c.div(mu).mulu(uint128(zx).pow(a, ONE))) <= MAX,
                    "YieldMath: Exchange rate overflow after trade"
                );

                // sum = za + ya - zxa
                require(
                    (sum = za + ya - zxa) <= MAX, // z < MAX, y < MAX, a < 1. It can only underflow, not overflow.
                    "YieldMath: Insufficient fyToken reserves"
                );
            }

            // result = fyTokenReserves - (sum ** (1/a))
            uint256 fyTokenOut;
            require(
                (fyTokenOut = uint256(fyTokenReserves) - uint256(uint128(sum).pow(ONE, a))) <= MAX,
                "YieldMath: Rounding induced error"
            );

            fyTokenOut = fyTokenOut < MAX - 1e12 ? fyTokenOut + 1e12 : MAX; // Add error guard, ceiling the result at max

            return uint128(fyTokenOut);
        }
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
    /// @return amount of Shares a user would get for given amount of fyToken
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
    ) private pure returns (uint128) {
        /* https://docs.google.com/spreadsheets/d/14K_McZhlgSXQfi6nFGwDvDh4BmOu6_Hczi_sFreFfOE/

            y = fyToken reserves
            z = base reserves
            x = Δy (fyTokenIn)

                 z - (                                rightSide                                              )
                 z - (invMu) * (      Za              ) + ( Ya   ) - (    Yxa      ) / (c / μ) )^(   invA    )
            Δz = z -   1/μ   * ( ( (c / μ) * (μz)^(1-t) +  y^(1-t) - (y + x)^(1-t) ) / (c / μ) )^(1 / (1 - t))

        */
        unchecked {
            // normalizedSharesReserves = μ * sharesReserves
            uint256 normalizedSharesReserves;
            require(
                (normalizedSharesReserves = mu.mulu(sharesReserves)) <= MAX,
                "YieldMath: Exchange rate overflow before trade"
            );

            int128 rightSide;
            {
                uint256 zaYaYxa;
                {
                    // za = c/μ * (normalizedSharesReserves ** a)
                    uint256 za;
                    require(
                        (za = c.div(mu).mulu(uint128(normalizedSharesReserves).pow(a, ONE))) <= MAX,
                        "YieldMath: Exchange rate overflow before trade"
                    );

                    // ya = fyTokenReserves ** a
                    uint256 ya = fyTokenReserves.pow(a, ONE);

                    // yxa = (fyTokenReserves + x) ** a   # x is aka Δy
                    uint256 yxa = (fyTokenReserves + fyTokenIn).pow(a, ONE);

                    require((zaYaYxa = (za + ya - yxa)) <= MAX, "YieldMath: Exchange rate overflow before trade");
                }

                rightSide = int128(ONE).div(mu).mul(
                    int128(uint128((zaYaYxa).divu(uint128(c.div(mu)))).pow(uint128(ONE), uint128(a)))
                );
            }
            require(rightSide <= int128(sharesReserves), "YieldMath: Exchange rate underflow before trade");

            return sharesReserves - uint128(rightSide);
        }
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
    ) public pure returns (uint128) {
        /* https://docs.google.com/spreadsheets/d/14K_McZhlgSXQfi6nFGwDvDh4BmOu6_Hczi_sFreFfOE/

                y = fyToken reserves
                z = base reserves
                x = Δz (sharesOut)

                     (                  sum                                )^(   invA    ) - y
                     (    Za          ) + (  Ya  ) - (       Zxa           )^(   invA    ) - y
                Δy = ( c/μ * (μz)^(1-t) +  y^(1-t) - c/μ * (μz - μx)^(1-t) )^(1 / (1 - t)) - y

            */

        unchecked {
            require(c > 0, "YieldMath: c must be positive");

            uint128 a = _computeA(timeTillMaturity, k, g);
            uint256 sum;
            {
                // normalizedSharesReserves = μ * sharesReserves
                uint256 normalizedSharesReserves;
                require(
                    (normalizedSharesReserves = mu.mulu(sharesReserves)) <= MAX,
                    "YieldMath: Exchange rate overflow before trade"
                );

                // za = c/μ * (normalizedSharesReserves ** a)
                uint256 za;
                require(
                    (za = c.div(mu).mulu(uint128(normalizedSharesReserves).pow(a, ONE))) <= MAX,
                    "YieldMath: Exchange rate overflow before trade"
                );

                // ya = fyTokenReserves ** a
                uint256 ya = fyTokenReserves.pow(a, ONE);

                // normalizedSharesOut = μ * sharesOut
                uint256 normalizedSharesOut;
                require(
                    (normalizedSharesOut = mu.mulu(sharesOut)) <= MAX,
                    "YieldMath: Exchange rate overflow before trade"
                );

                // zx = normalizedBaseReserves + sharesOut * μ
                require(normalizedSharesReserves >= normalizedSharesOut, "YieldMath: Too much shares in");
                uint256 zx = normalizedSharesReserves - normalizedSharesOut;

                // zxa = c/μ * zx ** a
                uint256 zxa;
                require(
                    (zxa = c.div(mu).mulu(uint128(zx).pow(a, ONE))) <= MAX,
                    "YieldMath: Exchange rate overflow after trade"
                );

                // sum = za + ya - zxa
                // z < MAX, y < MAX, a < 1. It can only underflow, not overflow.
                require((sum = za + ya - zxa) <= MAX, "YieldMath: Insufficient fyToken reserves");
            }
            // result = fyTokenReserves - (sum ** (1/a))
            uint256 result;
            require(
                (result = uint256(uint128(sum).pow(ONE, a)) - uint256(fyTokenReserves)) <= MAX,
                "YieldMath: Rounding induced error"
            );

            result = result > 1e12 ? result - 1e12 : 0; // Subtract error guard, flooring the result at zero

            return uint128(result);
        }
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
    /// @param fyTokenOut fyToken amount to be traded
    /// @param timeTillMaturity time till maturity in seconds e.g. 90 days in seconds
    /// @param k time till maturity coefficient, multiplied by 2^64.  e.g. 25 years in seconds
    /// @param g fee coefficient, multiplied by 2^64 -- sb under 1.0 for selling shares to pool
    /// @param c price of shares in terms of their base, multiplied by 2^64
    /// @param mu (μ) Normalization factor -- starts as c at initialization
    /// @return result the amount of shares a user would have to pay for given amount of fyToken
    function sharesInForFYTokenOut(
        uint128 sharesReserves,
        uint128 fyTokenReserves,
        uint128 fyTokenOut,
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
                    fyTokenOut,
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
        uint128 fyTokenOut,
        uint128 a,
        int128 c,
        int128 mu
    ) private pure returns (uint128) {
        /* https://docs.google.com/spreadsheets/d/14K_McZhlgSXQfi6nFGwDvDh4BmOu6_Hczi_sFreFfOE/

        y = fyToken reserves
        z = base reserves
        x = Δy (fyTokenOut)

             1/μ * (                 subtotal                            )^(   invA    ) - z
             1/μ * ((     Za       ) + (  Ya  ) - (    Yxa    )) / (c/μ) )^(   invA    ) - z
        Δz = 1/μ * (( c/μ * μz^(1-t) +  y^(1-t) - (y - x)^(1-t)) / (c/μ) )^(1 / (1 - t)) - z

        */
        unchecked {
            // normalizedSharesReserves = μ * sharesReserves
            require(mu.mulu(sharesReserves) <= MAX, "YieldMath: Exchange rate overflow before trade");

            // za = c/μ * (normalizedSharesReserves ** a)
            uint256 za = c.div(mu).mulu(uint128(mu.mulu(sharesReserves)).pow(a, ONE));
            require(za <= MAX, "YieldMath: Exchange rate overflow before trade");

            // ya = fyTokenReserves ** a
            uint256 ya = fyTokenReserves.pow(a, ONE);

            // yxa = (fyTokenReserves - x) ** aß
            uint256 yxa = (fyTokenReserves - fyTokenOut).pow(a, ONE);

            uint256 zaYaYxa;
            require((zaYaYxa = (za + ya - yxa)) <= MAX, "YieldMath: Exchange rate overflow before trade");

            int128 subtotal = int128(ONE).div(mu).mul(
                int128(uint128(zaYaYxa.divu(uint128(c.div(mu)))).pow(uint128(ONE), uint128(a)))
            );

            require(subtotal >= int128(sharesReserves), "YieldMath: Exchange rate underflow before trade");

            return uint128(subtotal) - sharesReserves;
        }
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

    //  This fn has never been finalized
    // /// @notice Calculates the max amount of fyToken that could go out based on current reserves.
    // /// @param sharesReserves yield bearing vault shares reserve amount
    // /// @param fyTokenReserves fyToken reserves amount
    // /// @param timeTillMaturity time till maturity in seconds e.g. 90 days in seconds
    // /// @param k time till maturity coefficient, multiplied by 2^64.  e.g. 25 years in seconds
    // /// @param g fee coefficient, multiplied by 2^64 -- sb under 1.0 for selling shares to pool
    // /// @param c price of shares in terms of their base, multiplied by 2^64
    // /// @param mu (μ) Normalization factor -- starts as c at initialization
    // /// @return fyTokenOut the amount of fyToken a user would get for given amount of shares
    // function maxFYTokenOut(
    //     uint128 sharesReserves, // z
    //     uint128 fyTokenReserves, // x
    //     uint128 timeTillMaturity,
    //     int128 k,
    //     int128 g,
    //     int128 c,
    //     int128 mu
    // ) public pure returns (uint128 fyTokenOut) {
    //     unchecked {
    //         require(c > 0 && mu > 0, "YieldMath: c and mu must be positive");
    //         return _maxFYTokenOut(sharesReserves, fyTokenReserves, _computeA(timeTillMaturity, k, g), c, mu);
    //     }
    // }

    // function _maxFYTokenOut(
    //     uint128 sharesReserves, // z
    //     uint128 fyTokenReserves, // y
    //     uint128 a,
    //     int128 c,
    //     int128 mu
    // ) internal pure returns (uint128) {
    //     /* https://docs.google.com/spreadsheets/d/14K_McZhlgSXQfi6nFGwDvDh4BmOu6_Hczi_sFreFfOE/

    //         dy = y - ((        numerator               ) / (    denominator               ))^(   invA  )
    //         dy = y - (( cμ^(1-t) * z^(1-t) + μ*y^(1-t) ) / (  c*μ^(1-t) * (1/c)^(1-t) + μ ))^( 1/(1-t) )

    //     Note: in the above equation t represents g * k * T
    //             (1-t) is calculated separately in computeA and thereafter referred to as 'a' */

    //     //                  termA       termB      termC
    //     // numerator =    cμ^(1-t)  * z^(1-t) +  mu * y^(1-t)
    //     int128 termA = c.mul(int128(uint128(mu).pow(a, ONE)));
    //     uint256 termB = sharesReserves.pow(a, ONE);
    //     uint256 termC = mu.mulu(fyTokenReserves.pow(a, ONE));
    //     uint256 numerator = termA.mulu(termB) + termC;

    //     // denominator =  c*μ^(1-t) * (1/c)^(1-t) + μ
    //     uint256 denominator = uint256(uint128(termA.mul(int128(uint128(int128(ONE).div(c)).pow(a, ONE))) + mu));
    //     // uint256 denominator = uint256(uint128(c.div(mu)).pow(t, ONE) + ONE);

    //     int128 result64 = fyTokenReserves.fromUInt() - int128(uint128(numerator / (denominator)).pow(ONE, a));
    //     // int128 result64 = fyTokenReserves.fromUInt() - int128(uint128(numerator / (denominator)).pow(ONE, a));
    //     // return result64.toUInt();
    // }

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
