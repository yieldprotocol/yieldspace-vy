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

    uint128 public constant sharesReserve = uint128(1100000 * 10**18); // Z
    uint128 public constant fyTokenReserve = uint128(900000 * 10**18); // Y
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
        assertTrue((expectedResult - result) <= 1);
    }

    /* 1. function fyTokenOutForSharesIn
     * https://www.desmos.com/calculator/bdplcpol2y
     ***************************************************************/
    // NOTE: MATH REVERTS WHEN ALL OF ONE RESOURCE IS DEPLETED

    function testUnit_fyTokenOutForSharesIn__baseCases() public {
        // should match Desmos for selected inputs
        uint128[4] memory baseAmounts = [
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
        for (uint256 idx; idx < baseAmounts.length; idx++) {
            emit log_named_uint("sharesAmount", baseAmounts[idx]);
            emit log_named_uint("sharesReserve", sharesReserve);
            result =
                VariableYieldMath.fyTokenOutForSharesIn(
                    sharesReserve,
                    fyTokenReserve,
                    baseAmounts[idx], // x or ΔZ
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

    function testUnit_fyTokenOutForSharesIn__atMaturity() public {
        //should have a price of one at maturity
        uint128 amount = uint128(100000 * 10**18);
        uint128 result = VariableYieldMath.fyTokenOutForSharesIn(
            sharesReserve,
            fyTokenReserve,
            amount,
            0,
            k,
            g1,
            c,
            mu
        ) / 10**18;
        uint128 expectedResult = uint128(amount * cNumerator / cDenominator) / 10 ** 18;

        // When rounding should round in favor of the pool
        assertSameOrSlightlyLess(result, expectedResult);
    }

    // TODO: should mirror sharesInforFyTokenOut


    // When t approaches 1, it becomes very similar to uniswap AMM pricing formula
    // As g increases, fyDaiIn increases (part of Alberto’s original tests in YieldspaceFarming repo)
    // Should revert if over reserves
    //
    function testUnit_fyTokenOutForSharesIn__wenBreak() public {
        uint128 result;
        for (uint256 idx; idx < 200; idx++) {
            emit log_named_uint("idx", idx);
            uint128 sharesAmount = (uint128(fyTokenReserve) *
                (uint128(idx) + 94900)) / 100000;
            emit log_named_uint("sharesAmount", sharesAmount);

            result = VariableYieldMath.fyTokenOutForSharesIn(
                sharesReserve,
                fyTokenReserve,
                sharesAmount,
                timeTillMaturity,
                k,
                g1,
                c,
                mu
            );

            emit log_named_uint("result", result);
            assertTrue(result > sharesAmount);
        }
    }

    function testFuzz_fyTokenOutForSharesIn(uint256 passedIn) public {
        uint128 sharesAmount = coerceUInt256To128(
            passedIn,
            1000000000000000000,
            949227786000000000000000
        );
        uint128 result = VariableYieldMath.fyTokenOutForSharesIn(
            sharesReserve,
            fyTokenReserve,
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
    // 105085 361790093746506072
    // function testUnit_old_fyTokenOutForSharesIn_VariableYieldMath() public {
    //     uint128[3] memory sharesReserveValues = [
    //         uint128(10000000000000000000000),
    //         100000000000000000000000000,
    //         1000000000000000000000000000000
    //     ];
    //     uint128[3] memory fyTokenReserveValues = [
    //         uint128(1000000000000000000000),
    //         10000000000000000000000000,
    //         10000000000000000000000000,
    //         100000000000000000000000000000
    //     ];
    //     uint128[3] memory baseAmountValues = [
    //         uint128(10000000000000000000),
    //         1000000000000000000000,
    //         100000000000000000000000
    //     ];
    //     uint128[3] memory timeTillMaturityValues = [
    //         uint128(1000000),
    //         1000000,
    //         1000000
    //     ];
    //     int128[3] memory gNumerator = [int128(9), 95, 975]; //NOTE: changed idx 2 from original because I think they were the same
    //     // https://github.com/yieldprotocol/YieldSpace-Farming/blob/dc3a61d290928cc921a9c482582bcf59083b692f/test/214_variable_yield_math_curve.ts#L80
    //     int128[3] memory gDenominator = [int128(10), 100, 1000];
    //     uint128 sharesReserve;
    //     uint128 fyTokenReserve;
    //     uint128 baseAmount;
    //     uint128 timeTillMaturity;
    //     int128 g;
    //     uint128 previousResult = uint128(0x0);
    //     uint128 result;
    //     for (uint256 i = 0; i < sharesReserveValues.length; i++) {
    //         sharesReserve = sharesReserveValues[i];
    //         fyTokenReserve = fyTokenReserveValues[i];
    //         baseAmount = baseAmountValues[i];
    //         timeTillMaturity = timeTillMaturityValues[i];

    //         for (uint256 j = 0; j < sharesReserveValues.length; j++) {
    //             g = (gNumerator[j] * b) / gDenominator[j];
    //             result = VariableYieldMath.fyTokenOutForSharesIn(
    //                 sharesReserve,
    //                 fyTokenReserve,
    //                 baseAmount,
    //                 timeTillMaturity,
    //                 k,
    //                 g,
    //                 ONE64,
    //                 ONE64
    //             );
    //             assertTrue(result > previousResult);
    //             // NOTE: changed from original (moved the above line into this loop) because I think it was a mistake
    //         }
    //         previousResult = result;
    //     }
    // }

    // function testFail_TooHigh_fromInt_Math64x64() public pure {
    //     Math64x64.fromInt(int256(0x7FFFFFFFFFFFFFFF + 1));
    // }

    // function testFail_TooLow_fromInt_Math64x64() public pure {
    //     Math64x64.fromInt(int256(-0x8000000000000000 - 1));
    // }

    // function testFuzz_fromInt_Math64x64(int256 passedIn) public {
    //     int256 from = coerceInt256To128(
    //         passedIn,
    //         -0x8000000000000000,
    //         0x7FFFFFFFFFFFFFFF
    //     );

    //     int128 result = Math64x64.fromInt(from);

    //     // Work backward to derive expected param
    //     int64 expectedFrom = Math64x64.toInt(result);
    //     assertEq(from, int256(expectedFrom));

    //     // Property Testing
    //     // fn(x) < fn(x + 1)
    //     bool overflows;
    //     unchecked {
    //         overflows = from > from + 1;
    //     }

    //     if (!overflows && (from + 1 <= 0x7FFFFFFFFFFFFFFF)) {
    //         assertTrue(Math64x64.fromInt(from + 1) > result);
    //     }
    //     // abs(fn(x)) < abs(x)
    //     assertTrue(abs(result) >= abs(from));
    // }
}
