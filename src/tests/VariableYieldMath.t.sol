// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.11;

import "ds-test/test.sol";

import {VariableYieldMath} from "./../contracts/VariableYieldMath.sol";
import "./helpers.sol";

contract VariableYieldMathTest is DSTest {
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
    ForTesting public forTesting;

    int128 immutable b;
    int128 immutable k;
    int128 immutable g1;
    int128 immutable g2;
    int128 immutable ONE64;

    constructor() {
        b = 18446744073709551615;
        k = b / 126144000;
        g1 = (950 * b) / 1000;
        g2 = (1000 * b) / 950;
        ONE64 = 18446744073709551616;
        forTesting = new ForTesting();

    }

    /* 1. function fyTokenOutForVyBaseIn
     ***************************************************************/

    function testUnit_fyTokenOutForVyBaseIn_VariableYieldMath() public {
        uint128[3] memory vyBaseReserveValues = [
            uint128(10000000000000000000000),
            100000000000000000000000000,
            1000000000000000000000000000000
        ];
        uint128[3] memory fyTokenReserveValues = [
            uint128(1000000000000000000000),
            10000000000000000000000000,
            100000000000000000000000000000
        ];
        uint128[3] memory baseAmountValues = [
            uint128(10000000000000000000),
            1000000000000000000000,
            100000000000000000000000
        ];
        uint128[3] memory timeTillMaturityValues = [
            uint128(1000000),
            1000000,
            1000000
        ];
        int128[3] memory gNumerator = [int128(9), 95, 950];
        int128[3] memory gDenominator = [int128(10), 100, 1000];
        uint128 vyBaseReserve;
        uint128 fyTokenReserve;
        uint128 baseAmount;
        uint128 timeTillMaturity;
        int128 g;
        for (uint256 index = 0; index < vyBaseReserveValues.length; index++) {
            vyBaseReserve = vyBaseReserveValues[index];
            fyTokenReserve = fyTokenReserveValues[index];
            baseAmount = baseAmountValues[index];
            timeTillMaturity = timeTillMaturityValues[index];
            g = (gNumerator[index] * b) / gDenominator[index];
            uint128 result1 = VariableYieldMath.fyTokenOutForVyBaseIn(
                vyBaseReserve,
                fyTokenReserve,
                baseAmount,
                timeTillMaturity,
                k,
                g,
                ONE64
            );

            uint128 result2 = VariableYieldMath.fyTokenOutForVyBaseIn(
                vyBaseReserve,
                fyTokenReserve,
                baseAmount,
                timeTillMaturity,
                k,
                (int128(11) / int128(10)) * g, // increase g by 10%
                ONE64
            );

            assertTrue(result1 <= result2); // TODO: is <= ok here?
        }
    }

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
