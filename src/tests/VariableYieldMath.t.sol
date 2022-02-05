// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.11;

import "ds-test/test.sol";

import {VariableYieldMath} from "./../contracts/VariableYieldMath.sol";
import {Math64x64} from "./../contracts/Math64x64.sol";
import {Exp64x64} from "./../contracts/Exp64x64.sol";

import "./helpers.sol";

contract VariableYieldMathTest is DSTest {
    using Math64x64 for int128;
    using Math64x64 for uint128;
    using Math64x64 for int256;
    using Math64x64 for uint256;
    using Exp64x64 for uint128;

    /**TESTS*********************************************************

        Tests grouped by function:


        Test name prefixe definitions:
        testUnit_          - Unit tests for common edge cases
        testFail_<reason>_ - Unit tests code reverts appropriately
        testFuzz_          - Property based fuzz tests
        prove_             - Symbolic execution
        NOTE: Symbolic execution tests found in separate file:
        VariableYieldMathSymbolicExecution.t.sol

        <NAME OF TEST> = <prefix>_<name of function being tested>_<name of library>

        example:
        testFuzz_someFunc_SomeLib = fuzz testing on function named someFunc in SomeLib
        testFail_Unauthorized_someFunc_SomeLib = test reverts when unauthorized

    ****************************************************************/

    // create an external contract for use with try/catch
    // ForTesting public forTesting;

    uint128 public constant sharesReserves = uint128(1100000 * 10**18); // Z
    uint128 public constant fyTokenReserves = uint128(900000 * 10**18); // Y
    uint128 public constant timeTillMaturity = uint128(90 * 24 * 60 * 60); // T

    int128 immutable k;

    uint256 public constant gNumerator = 95;
    uint256 public constant gDenominator = 100;
    int128 public g1; // g to use when selling shares to pool
    int128 public g2; // g to use when selling fyTokens to pool

    uint256 public constant cNumerator = 11;
    uint256 public constant cDenominator = 10;
    int128 public c;

    uint256 public constant muNumerator = 105;
    uint256 public constant muDenominator = 100;
    int128 public mu;

    constructor() {
        uint256 invK = 25 * 365 * 24 * 60 * 60;
        k = uint256(1).fromUInt().div(invK.fromUInt());

        g1 = gNumerator.fromUInt().div(gDenominator.fromUInt());
        g2 = gDenominator.fromUInt().div(gNumerator.fromUInt());
        c = cNumerator.fromUInt().div(cDenominator.fromUInt());
        mu = muNumerator.fromUInt().div(muDenominator.fromUInt());
        // forTesting = new ForTesting();
    }

    function assertSameOrSlightlyLess(uint128 result, uint128 expectedResult)
        public
    {
        emit log_named_uint("diff", expectedResult - result);
        assertTrue((expectedResult - result) <= 1);
    }

    function assertSameOrSlightlyMore(uint128 result, uint128 expectedResult)
        public
    {
        assertTrue((result - expectedResult) <= 1);
    }

    /* 1. function fyTokenOutForSharesIn
     * https://www.desmos.com/calculator/7iebbri94t
     ***************************************************************/
    // NOTE: MATH REVERTS WHEN ALL OF ONE RESOURCE IS DEPLETED

    function testUnit_fyTokenOutForSharesIn__baseCases() public {
        // should match Desmos for selected inputs
        uint128[4] memory sharesAmounts = [
            uint128(50000 * 10**18),
            uint128(100000 * 10**18),
            uint128(200000 * 10**18),
            uint128(830240163000000000000000)
        ];
        uint128[4] memory expectedResults = [
            uint128(54844),
            uint128(109632),
            uint128(219036),
            uint128(900000)
        ];
        uint128 result;
        for (uint256 idx; idx < sharesAmounts.length; idx++) {
            emit log_named_uint("sharesAmount", sharesAmounts[idx]);
            emit log_named_uint("sharesReserves", sharesReserves);
            result =
                VariableYieldMath.fyTokenOutForSharesIn(
                    sharesReserves,
                    fyTokenReserves,
                    sharesAmounts[idx], // x or ΔZ
                    timeTillMaturity,
                    k,
                    g1,
                    c,
                    mu
                ) /
                10**18;
            emit log_named_uint("result", result);
            emit log_named_uint("expectedResult", expectedResults[idx]);

            // When rounding should round in favor of the pool
            assertSameOrSlightlyLess(result, expectedResults[idx]);
        }
    }

    function testUnit_fyTokenOutForSharesIn__mirror() public {
        // should match Desmos for selected inputs
        uint128[4] memory sharesAmounts = [
            uint128(50000 * 10**18),
            uint128(100000 * 10**18),
            uint128(200000 * 10**18),
            uint128(830240163000000000000000)
        ];
        uint128 result;
        for (uint256 idx; idx < sharesAmounts.length; idx++) {
            emit log_named_uint("sharesAmount", sharesAmounts[idx]);
            emit log_named_uint("sharesReserves", sharesReserves);
            result =
                VariableYieldMath.fyTokenOutForSharesIn(
                    sharesReserves,
                    fyTokenReserves,
                    sharesAmounts[idx], // x or ΔZ
                    timeTillMaturity,
                    k,
                    g1,
                    c,
                    mu
                );
            emit log_named_uint("result", result);
            uint128 resultShares = VariableYieldMath.sharesInForFyTokenOut(
                sharesReserves,
                fyTokenReserves,
                result,
                timeTillMaturity,
                k,
                g1,
                c,
                mu
            );
            emit log_named_uint("resultShares", resultShares);

            assertSameOrSlightlyLess(resultShares / 10 ** 18, sharesAmounts[idx] / 10 ** 18);
        }
    }

    function testUnit_fyTokenOutForSharesIn__atMaturity() public {
        //should have a price of one at maturity
        uint128 amount = uint128(100000 * 10**18);
        uint128 result = VariableYieldMath.fyTokenOutForSharesIn(
            sharesReserves,
            fyTokenReserves,
            amount,
            0,
            k,
            g1,
            c,
            mu
        ) / 10**18;
        uint128 expectedResult = uint128((amount * cNumerator) / cDenominator) /
            10**18;

        // When rounding should round in favor of the pool
        assertSameOrSlightlyLess(result, expectedResult);
    }

    function testUnit_fyTokenOutForSharesIn__increaseG() public {
        // increase in g results in increase in fyTokenOut
        // NOTE: potential fuzz test
        uint128 amount = uint128(100000 * 10**18);
        uint128 result1 = VariableYieldMath.fyTokenOutForSharesIn(
            sharesReserves,
            fyTokenReserves,
            amount,
            timeTillMaturity,
            k,
            g1,
            c,
            mu
        ) / 10**18;

        int128 bumpedG = uint256(975).fromUInt().div(gDenominator.fromUInt());
        uint128 result2 = VariableYieldMath.fyTokenOutForSharesIn(
            sharesReserves,
            fyTokenReserves,
            amount,
            timeTillMaturity,
            k,
            bumpedG,
            c,
            mu
        ) / 10**18;
        assertTrue(result2 > result1);
    }

    function testFuzz_fyTokenOutForSharesIn(uint256 passedIn) public {
        uint128 sharesAmount = coerceUInt256To128(
            passedIn,
            1000000000000000000,
            949227786000000000000000
        );
        uint128 result = VariableYieldMath.fyTokenOutForSharesIn(
            sharesReserves,
            fyTokenReserves,
            sharesAmount, // x or ΔZ
            timeTillMaturity,
            k,
            g1,
            c,
            mu
        );

        if (result < sharesAmount) {
            emit log_named_uint("sharesAmount", sharesAmount);
            emit log_named_uint("result", result);
        }
        assertTrue(result > sharesAmount);
    }


    // As g increases, fyDaiIn increases (part of Alberto’s original tests in YieldspaceFarming repo)
    //
    // TODO: Should revert if over reserves


    /* 2. function sharesInForFyTokenOut
     *
     ***************************************************************/
    // NOTE: MATH REVERTS WHEN ALL OF ONE RESOURCE IS DEPLETED
    function testUnit_sharesInForFyTokenOut__baseCases() public {
        // should match Desmos for selected inputs
        uint128[4] memory fyTokenAmounts = [
            uint128(50000 * 10**18),
            uint128(100000 * 10**18),
            uint128(200000 * 10**18),
            uint128(900000 * 10**18)
        ];
        uint128[4] memory expectedResults = [
            uint128(45581),
            uint128(91205),
            uint128(182584),
            uint128(830240)
        ];
        uint128 result;
        for (uint256 idx; idx < fyTokenAmounts.length; idx++) {
            emit log_named_uint("fyTokenAmount", fyTokenAmounts[idx]);
            emit log_named_uint("fyTokenReserves", fyTokenReserves);
            result =
                VariableYieldMath.sharesInForFyTokenOut(
                    sharesReserves,
                    fyTokenReserves,
                    fyTokenAmounts[idx], // x or ΔZ
                    timeTillMaturity,
                    k,
                    g1,
                    c,
                    mu
                ) /
                10**18;
            emit log_named_uint("result", result);
            emit log_named_uint("expectedResult", expectedResults[idx]);

            // When rounding should round in favor of the pool
            assertSameOrSlightlyMore(result, expectedResults[idx]);
        }
    }

    function testUnit_sharesInForFyTokenOut__atMaturity() public {
        //should have a price of one at maturity
        uint128 baseAmount = uint128(100000 * 10**18);
        uint128 amount = uint128((baseAmount * cNumerator) / cDenominator);
        uint128 result = VariableYieldMath.sharesInForFyTokenOut(
            sharesReserves,
            fyTokenReserves,
            amount,
            0,
            k,
            g1,
            c,
            mu
        ) / 10**18;
        uint128 expectedResult = baseAmount / 10**18;
        emit log_named_uint("result", result);
        emit log_named_uint("expectedResult", expectedResult);

        // When rounding should round in favor of the pool
        assertSameOrSlightlyMore(result, expectedResult);
    }

    function testUnit_sharesInForFyTokenOut__mirror() public {
        // should match Desmos for selected inputs
        uint128[4] memory fyTokenAmounts = [
            uint128(50000 * 10**18),
            uint128(100000 * 10**18),
            uint128(200000 * 10**18),
            uint128(830240163000000000000000)
        ];
        uint128 result;
        for (uint256 idx; idx < fyTokenAmounts.length; idx++) {
            emit log_named_uint("fyTokenAmount", fyTokenAmounts[idx]);
            emit log_named_uint("fyTokenReserves", fyTokenReserves);
            result =
                VariableYieldMath.fyTokenOutForSharesIn(
                    sharesReserves,
                    fyTokenReserves,
                    fyTokenAmounts[idx], // x or ΔZ
                    timeTillMaturity,
                    k,
                    g1,
                    c,
                    mu
                );
            emit log_named_uint("result", result);
            uint128 resultFyTokens = VariableYieldMath.sharesInForFyTokenOut(
                sharesReserves,
                fyTokenReserves,
                result,
                timeTillMaturity,
                k,
                g1,
                c,
                mu
            );
            emit log_named_uint("resultFyTokens", resultFyTokens);
            assertSameOrSlightlyMore(resultFyTokens / 10 ** 18, fyTokenAmounts[idx] / 10 ** 18);
        }
    }

    /* 3. function sharesOutForFyTokenIn
     *
     ***************************************************************/

    function testUnit_sharesOutForFyTokenIn__baseCases() public {
        // should match Desmos for selected inputs
        uint128[1] memory fyTokenAmounts = [
            // uint128(50000 * 10**18),
            // uint128(100000 * 10**18),
            // uint128(200000 * 10**18),
            uint128(50000 * 10 ** 18)
        ];
        uint128[1] memory expectedResults = [
            // uint128(45581),
            // uint128(91205),
            // uint128(182584),
            uint128(45549)
        ];
        uint128 result;
        for (uint256 idx; idx < fyTokenAmounts.length; idx++) {
            emit log_named_uint("fyTokenAmount", fyTokenAmounts[idx]);
            emit log_named_uint("fyTokenReserves", fyTokenReserves);
            result =
                VariableYieldMath.sharesOutForFyTokenIn(
                    sharesReserves,
                    fyTokenReserves,
                    fyTokenAmounts[idx], // x or ΔZ
                    timeTillMaturity,
                    k,
                    g2,
                    c,
                    mu
                ) /
                10**18;
            emit log_named_uint("result", result);
            emit log_named_uint("expectedResult", expectedResults[idx]);

            // When rounding should round in favor of the pool
            assertSameOrSlightlyMore(result, expectedResults[idx]);
        }
    }


    /* 4. function fyTokenInForSharesOut
     *
     ***************************************************************/
    function testUnit_fyTokenInForSharesOut__baseCases() public {
        // should match Desmos for selected inputs
        uint128[1] memory sharesAmounts = [
            // uint128(50000 * 10**18),
            // uint128(100000 * 10**18),
            // uint128(200000 * 10**18),
            uint128(50000 * 10**18)
        ];
        uint128[1] memory expectedResults = [
            // uint128(45581),
            // uint128(91205),
            // uint128(182584),
            uint128(54887)
        ];
        uint128 result;
        for (uint256 idx; idx < sharesAmounts.length; idx++) {
            emit log_named_uint("fyTokenAmount", sharesAmounts[idx]);
            emit log_named_uint("fyTokenReserves", sharesReserves);
            result =
                VariableYieldMath.fyTokenInForSharesOut(
                    sharesReserves,
                    fyTokenReserves,
                    sharesAmounts[idx], // x or ΔZ
                    timeTillMaturity,
                    k,
                    g2,
                    c,
                    mu
                ) /
                10**18;
            emit log_named_uint("result", result);
            emit log_named_uint("expectedResult", expectedResults[idx]);

            // When rounding should round in favor of the pool
            assertSameOrSlightlyMore(result, expectedResults[idx]);
        }
    }


}
