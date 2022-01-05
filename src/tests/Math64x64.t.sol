// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.11;

import "ds-test/test.sol";

import "./../contracts/Math64x64.sol";
import "./helpers.sol";

contract Math64x64Test is DSTest {
    /**TESTS*********************************************************

        Tests grouped by function:
        1.  function fromInt(int256 x) internal pure returns (int128)
        2.  function toInt(int128 x) internal pure returns (int64)
        3.  function fromUInt(uint256 x) internal pure returns (int128)
        4.  function toUInt (int128 x) internal pure returns (uint64)
        5.  function (int256 x) internal pure returns (int128)
        6.  function add (int128 x, int128 y) internal pure returns (int128)
        7.  function sub (int128 x, int128 y) internal pure returns (int128)
        8.  function  (int128 x, int128 y) internal pure returns (int128)
        9.  function muli (int128 x, int256 y) internal pure returns (int256)
        10. function mulu (int128 x, uint256 y) internal pure returns (uint256)
        11. function div (int128 x, int128 y) internal pure returns (int128)
        12. divi (int256 x, int256 y) internal pure returns (int128)

        Test name prefixe definitions:
        testUnit          - Unit tests for common edge cases
        testFail<reason>  - Unit tests code reverts appropriately
        testFuzz          - Property based fuzz tests
        prove             - Symbolic execution
        NOTE: Symbolic execution tests found in separate file:
        Math64x64SymbolicExecution.t.sol

        <NAME OF TEST> = prefix + "Fn" + name of function being tested

        example:
        testFuzzFnSomeFunc = fuzz testing on function named someFunc
        testFailUnauthorizedFnSomeFunc = test reverts when unauthorized

    ****************************************************************/

    /* 1. function fromInt(int256 x) internal pure returns (int128)
     ***************************************************************/

    function testUnitFnFromInt() public {
        int256[9] memory fromValues = [
            int256(0x7FFFFFFFFFFFFFFF),
            int256(0x7FFFFFFFFFFFFFFF - 1),
            int256(0x2),
            int256(0x1),
            int256(0x0),
            int256(-0x1),
            int256(-0x2),
            int256(-0x8000000000000000 + 1),
            int256(-0x8000000000000000)
        ];
        int256 from;
        for (uint256 index = 0; index < fromValues.length; index++) {
            from = fromValues[index];
            int128 result = Math64x64.fromInt(from);

            // Re-implement logic from lib to derive expected result
            int128 expectedResult = int128(from << 64);

            assertEq(expectedResult, result);
        }
    }

    function testFailTooHighFnFromInt() public pure {
        Math64x64.fromInt(int256(0x7FFFFFFFFFFFFFFF + 1));
    }

    function testFailTooLowFnFromInt() public pure {
        Math64x64.fromInt(int256(-0x8000000000000000 - 1));
    }

    function testFuzzFnFromInt(int256 passedIn) public {
        int256 from = coerce256IntTo128(passedIn, -0x8000000000000000, 0x7FFFFFFFFFFFFFFF);

        int128 result = Math64x64.fromInt(from);

        // Work backward to derive expected param
        int64 expectedFrom = Math64x64.toInt(result);
        assertEq(from, int256(expectedFrom));

        // Property Testing
        // fn(x) < fn(x + 1)
        bool overflows;
        unchecked {
            overflows = from > from + 1;
        }

        if (!overflows && (from + 1 <= 0x7FFFFFFFFFFFFFFF)) {
            assertTrue(Math64x64.fromInt(from + 1) > result);
        }
        // abs(fn(x)) < abs(x)
        assertTrue(abs(result) >= abs(from));
    }

    /* 2. function toInt(int128 x) internal pure returns (int64)
     ***************************************************************/
    function testUnitFnToInt() public {
        int128[11] memory toValues = [
            type(int128).max,
            int128(0x7fffffffffffffff0000000000000000),
            int128(0x7FFFFFFFFFFFFFFF),
            int128(0x2),
            int128(0x1),
            int128(0x0),
            int128(-0x1),
            int128(-0x2),
            int128(-0x8000000000000000),
            int128(-0x80000000000000000000000000000000 + 1),
            type(int128).min
        ];
        int128 to;
        for (uint256 index = 0; index < toValues.length; index++) {
            to = toValues[index];
            int64 result = Math64x64.toInt(to);

            // Re-implement logic from lib to derive expected result
            int64 expectedResult = int64(to >> 64);

            assertEq(expectedResult, result);
        }
    }

    function testFuzzFnToInt(int256 passedIn) public {
        int128 to = coerce256IntTo128(passedIn);

        int64 result = Math64x64.toInt(to);

        // Re-implement logic from lib to derive expected result
        int64 expectedResult = int64(to >> 64);
        assertEq(expectedResult, result);

        // Property Testing
        // fn(x) < fn(x + 1)
        bool overflows;
        unchecked {
            overflows = to > to + 1;
        }
        if (!overflows) {
            assertTrue(Math64x64.toInt(to + 1) >= result);
        }

        // abs(fn(x)) < abs(x)
        assertTrue(abs(result) <= abs(to));
    }

    /* 3. function fromUInt(uint256 x) internal pure returns (int128)
     ***************************************************************/
    function testUnitFnFromUInt() public {
        uint256[5] memory fromValues = [
            uint256(0x7fffffffffffffff),
            uint256(0x7fffffffffffffff - 1),
            uint256(0x2),
            uint256(0x1),
            type(uint256).min
        ];
        uint256 from;
        for (uint256 index = 0; index < fromValues.length; index++) {
            from = fromValues[index];
            int128 result = Math64x64.fromUInt(from);

            // Re-implement logic from lib to derive expected result
            int128 expectedResult = int128(uint128(from << 64));
            assertEq(expectedResult, result);
        }
    }

    function testFailTooHighFnFromUInt() public pure {
        Math64x64.fromUInt(uint256(0x7FFFFFFFFFFFFFFF + 1));
    }

    function testFuzzFnFromUInt(uint256 passedIn) public {
        uint256 from = passedIn % (0x7FFFFFFFFFFFFFFF + 1);

        int128 result = Math64x64.fromUInt(from);

        // Re-implement logic from lib to derive expected result
        int128 expectedResult = int128(uint128(from << 64));

        assertEq(expectedResult, result);

        // Work backward to derive expected param
        uint256 expectedFrom = uint256(uint128(result >> 64));
        assertEq(from, expectedFrom);

        // Property Testing
        // fn(x) < fn(x + 1)
        bool overflows;
        unchecked {
            overflows = from > from + 1;
        }

        if (!overflows && (from + 1 <= 0x7FFFFFFFFFFFFFFF)) {
            assertTrue(Math64x64.fromUInt(from + 1) > result);
        }
        // fn(x) >= x
        assertTrue(uint256(uint128(result)) >= from);
    }

    /* 4. function toUInt (int128 x) internal pure returns (uint64)
     ***************************************************************/
    function testUnitFnToUInt() public {
        int128[8] memory toValues = [
            type(int128).max,
            int128(0x7fffffffffffffff + 1),
            int128(0x7fffffffffffffff),
            int128(0x7ffffffffffffff - 1),
            int128(type(int64).max),
            int128(0x2),
            int128(0x1),
            int128(0x0)
        ];
        int128 to;
        for (uint256 index = 0; index < toValues.length; index++) {
            to = toValues[index];
            uint64 result = Math64x64.toUInt(to);

            // Re-implement logic from lib to derive expected result
            uint64 expectedResult = uint64(int64(to >> 64));

            assertEq(expectedResult, result);
        }
    }

    function testFailNegativeNumberFnToUInt() public pure {
        Math64x64.toUInt(-1);
    }

    function testFuzzFnToUInt(int256 passedIn) public {
        int128 to = coerce256IntTo128(passedIn);

        int64 result = Math64x64.toInt(to);

        // Re-implement logic from lib to derive expected result
        int128 expectedResult = int64(to >> 64);
        assertEq(expectedResult, result);

        // Property Testing
        // fn(x) < fn(x + 1)
        bool overflows;
        unchecked {
            overflows = to > to + 1;
        }
        if (!overflows) {
            assertTrue(Math64x64.toInt(to + 1) >= result);
        }

        // abs(fn(x)) < abs(x)
        assertTrue(abs(result) <= abs(to));
    }

    /* 5. function (int256 x) internal pure returns (int128)
     ***************************************************************/
    function testUnitFnTo128x128() public {
        int128[11] memory toValues = [
            type(int128).max,
            int128(0x7fffffffffffffff0000000000000000),
            int128(0x7FFFFFFFFFFFFFFF),
            int128(0x2),
            int128(0x1),
            int128(0x0),
            int128(-0x1),
            int128(-0x2),
            int128(-0x8000000000000000),
            int128(-0x80000000000000000000000000000000 + 1),
            type(int128).min
        ];
        int128 to;
        for (uint256 index = 0; index < toValues.length; index++) {
            to = toValues[index];
            int256 result = Math64x64.to128x128(to);

            // Re-implement logic from lib to derive expected result
            int256 expectedResult = int256(to) << 64;

            assertEq(expectedResult, result);
        }
    }

    function testFuzzFnTo128x128(int256 passedIn) public {
        int128 to = coerce256IntTo128(passedIn);

        int256 result = Math64x64.to128x128(to);

        // Re-implement logic from lib to derive expected result
        int256 expectedResult = int256(to) << 64;

        assertEq(expectedResult, result);

        // Property Testing
        // fn(x) < fn(x + 1)
        bool overflows;
        unchecked {
            overflows = to > to + 1;
        }
        if (!overflows) {
            assertTrue(Math64x64.to128x128(to + 1) >= result);
        }
    }

    /* 6. function add (int128 x, int128 y) internal pure returns (int128)
     ***************************************************************/
    function testUnitFnAdd() public {
        int128[9] memory xValues = [
            type(int128).min,
            int128(-0x1000),
            int128(-0x1),
            int128(0x0),
            int128(0x0),
            int128(0x1),
            int128(0x1),
            int128(0x1000),
            int128(type(int64).max)
        ];
        int128[9] memory yValues = [
            int128(type(int64).max),
            int128(-0x1),
            int128(0x1),
            int128(0x0),
            int128(0x0),
            type(int128).min,
            int128(-0x1000),
            int128(0x1),
            int128(0x1000)
        ];
        int128 x;
        int128 y;
        for (uint256 index = 0; index < xValues.length; index++) {
            x = xValues[index];
            y = yValues[index];
            int128 result = Math64x64.add(x, y);

            // Re-implement logic from lib to derive expected result
            int128 expectedResult = x + y;

            assertEq(expectedResult, result);
        }
    }

    function testFailOverflowFnAdd() public pure {
        Math64x64.add(type(int128).max, 1);
    }

    function testFailUnderflowFnAdd() public pure {
        Math64x64.add(type(int128).min, -1);
    }

    // NOTE: No fuzz tests for add() ^^ because too many cases would result in overflow.
    // See symbolic exec testing at: proveFnAdd() in Math64x64SymbolicExecution.t.sol

    /* 7. function sub (int128 x, int128 y) internal pure returns (int128)
     ***************************************************************/
    function testUnitFnSub() public {
        int128[9] memory xValues = [
            type(int128).max,
            type(int128).min,
            int128(-0x1),
            int128(0x0),
            int128(0x0),
            int128(-0x1),
            int128(0x1),
            int128(0x1000),
            type(int128).min
        ];
        int128[9] memory yValues = [
            type(int128).max,
            int128(-0x1),
            int128(0x1),
            int128(0x0),
            int128(0x0),
            type(int128).min,
            int128(-0x1000),
            int128(0x1),
            type(int128).min
        ];
        int128 x;
        int128 y;
        for (uint256 index = 0; index < xValues.length; index++) {
            x = xValues[index];
            y = yValues[index];
            int128 result = Math64x64.sub(x, y);

            // Re-implement logic from lib to derive expected result
            int128 expectedResult = x - y;

            assertEq(expectedResult, result);
        }
    }

    function testFailOverflowFnSub() public pure {
        Math64x64.sub(type(int128).max, -1);
    }

    function testFailUnderflowFnSub() public pure {
        Math64x64.sub(type(int128).min, 1);
    }

    // NOTE: No fuzz tests for sub() ^^ because too many cases would result in overflow.
    // See symbolic exec testing at: proveFnSub() in Math64x64SymbolicExecution.t.sol

    /* 8. function mul (int128 x, int128 y) internal pure returns (int128)
     ***************************************************************/
    function testUnitFnMul() public {
        int128[11] memory xValues = [
            type(int128).max,
            type(int128).max,
            type(int128).max,
            type(int128).min,
            type(int128).min,
            type(int128).min,
            int128(-0x1),
            int128(0x0),
            int128(0x0),
            int128(-0x1),
            int128(0x30)
        ];
        int128[11] memory yValues = [
            int128(0x1),
            int128(0x0),
            int128(-0x1),
            int128(0x1),
            int128(0x0),
            int128(-0x1),
            int128(0x1),
            int128(0x0),
            int128(-0x1),
            int128(0x1),
            int128(0x20)
        ];
        int128 x;
        int128 y;
        int256 result;
        int256 expectedResult;
        for (uint256 index = 0; index < xValues.length; index++) {
            x = xValues[index];
            y = yValues[index];
            result = Math64x64.mul(x, y);

            // Re-implement logic from lib to derive expected result
            expectedResult = (int256(x) * y) >> 64;

            assertEq(expectedResult, result);
        }
    }

    function testFailOverflowFnMul() public pure {
        Math64x64.mul(type(int128).max, type(int128).max);
    }

    function testFailUnderflowFnMul() public pure {
        Math64x64.mul(type(int128).min, type(int128).max);
    }

    // NOTE: No fuzz tests for mul() ^^ because too many cases would result in overflow.
    // See symbolic exec testing at: proveFnMul() in Math64x64SymbolicExecution.t.sol

    /* 9. function muli (int128 x, int256 y) internal pure returns (int256) {
     ***************************************************************/
    function testUnitFnMuli() public {
        int128[9] memory xValues = [
            type(int128).min,
            type(int128).min,
            type(int128).min,
            0x1,
            0x0,
            -0x1,
            type(int128).max,
            type(int128).max,
            type(int128).max
        ];
        int256[9] memory yValues = [
            int256(-0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF),
            0x0,
            int256(0x1000000000000000000000000000000000000000000000000),
            0x1,
            0x0,
            -0x1,
            0x0,
            0x1,
            -0x1
        ];
        int128 x;
        int256 y;
        int256 result;
        int256 expectedResult;
        for (uint256 index = 0; index < xValues.length; index++) {
            x = xValues[index];
            y = yValues[index];
            result = Math64x64.muli(x, y);
            // Re-implement logic from lib to derive expected result
            if (x == type(int128).min) {
                expectedResult = -y << 63;
            } else {
                bool negativeResult = false;
                if (x < 0) {
                    x = -x;
                    negativeResult = true;
                }
                if (y < 0) {
                    y = -y; // We rely on overflow behavior here
                    negativeResult = !negativeResult;
                }
                uint256 absoluteResult = Math64x64.mulu(x, uint256(y));
                if (negativeResult) {
                    expectedResult = -int256(absoluteResult); // We rely on overflow behavior here
                } else {
                    expectedResult = int256(absoluteResult);
                }
            }

            assertEq(expectedResult, result);
        }
    }

    function testFailOverflowFnMuli() public pure {
        Math64x64.muli(type(int128).max, type(int256).max);
    }

    function testFailUnderflowFnMuli() public pure {
        Math64x64.muli(type(int128).min, type(int256).max);
    }

    /**
     * NOTE: This Math64x64.muli logic is too complex to test w symbolic execution
     * but also is subject to false positive results when fuzzing due to the potential
     * for a large percentage of test cases being skipped when passed in parameters
     * fall outside certain conditions found in Math64x64.mulu.
     * Recommended: Deep fuzzing w 10,000 runs or more
     */
    function testFuzzFnMuli(int256 passedInX, int256 y) public {
        int128 x = coerce256IntTo128(passedInX);

        if (y == type(int256).min) return;

        int256 expectedResult;
        // Re-implement logic from lib to derive expected result
        if (x == type(int128).min) {
            if (
                !(y >= -0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF &&
                    y <= 0x1000000000000000000000000000000000000000000000000)
            ) return;
            expectedResult = -y << 63;
        } else {
            bool negativeResult = false;
            if (x < 0) {
                x = -x;
                negativeResult = true;
            }
            if (y < 0) {
                y = -y; // We rely on overflow behavior here
                negativeResult = !negativeResult;
            }

            // mulu checks
            uint256 lo = (uint256(int256(x)) *
                uint256((y) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)) >> 64;
            uint256 hi = uint256(int256(x)) * (uint256(y) >> 128);

            if (hi > 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF) return;
            hi <<= 64;
            if (
                hi >
                uint256(
                    0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
                ) -
                    lo
            ) return;

            uint256 absoluteResult = Math64x64.mulu(x, uint256(y));
            if (negativeResult) {
                expectedResult = -int256(absoluteResult); // We rely on overflow behavior here
            } else {
                expectedResult = int256(absoluteResult);
            }
        }
        int256 result = Math64x64.muli(x, y);
        assertEq(expectedResult, result);
    }

    /* 10. function mulu (int128 x, uint256 y) internal pure returns (uint256)
     ***************************************************************/
    // NOTE: Math64x64.mulu is tested indirectly through the muli tests
    // No additional testing is deemed necessary

    /* 11. function div (int128 x, int128 y) internal pure returns (int128)
     ***************************************************************/
    function testUnitFnDiv() public {
        int128[10] memory xValues = [
            type(int128).min, // 0
            type(int128).min, // 1
            0x0, // 3
            0x1, // 4
            type(int128).max, // 5
            type(int128).max, // 6
            -0x1, // 7
            -0x20, // 8
            0x100, // 9
            -0x100 // 10
        ];
        int128[10] memory yValues = [
            type(int128).min, // 0
            type(int128).max, // 1
            type(int128).max, // 3
            0x1, // 4
            type(int128).max, // 5
            type(int128).min, // 6
            type(int128).min, // 7
            0x30, // 8
            0x40, // 9
            -0x200 // 10
        ];
        int128 x;
        int128 y;
        int128 result;
        int128 expectedResult;
        for (uint256 index = 0; index < xValues.length; index++) {
            x = xValues[index];
            y = yValues[index];
            result = Math64x64.div(x, y);

            // Re-implement logic from lib to derive expected result
            expectedResult = int128((int256(x) << 64) / y);
            assertEq(expectedResult, result);
        }
    }

    function testFailDivByZeroFnDiv() public pure {
        Math64x64.div(type(int128).max, 0x0);
    }

    function testFuzzFnDiv(int256 passedInX, int256 passedInY) public {
        if (passedInY == 0) return;
        int128 x = coerce256IntTo128(passedInX);
        int128 y = coerce256IntTo128(passedInY);

        // Re-implement logic from lib to derive expected result
        int256 expectedResult256 = (int256(x) << 64) / y;
        if (
            expectedResult256 > type(int128).max ||
            expectedResult256 < type(int128).min
        ) return;

        int128 expectedResult = int128(expectedResult256);

        int128 result = Math64x64.div(x, y);

        assertEq(expectedResult, result);
    }

    /* 12. divi (int256 x, int256 y) internal pure returns (int128)
     ***************************************************************/
    function testUnitFnDivI() public {
        int256[3] memory xValues = [
            // int256(type(int128).min),  //NOTE: NOT SURE THE LIB HANDLES THIS CORRECTLY
            int256(0x0),
            0x1,
            // int256(type(int128).max), // NOTE: CAN'T GET IT TO WORK W MIN OR MAX IN NUMERATOR
            int256(-0x100)
        ];
        int256[3] memory yValues = [
            int256(0x1),
            // int256(type(int128).max),
            0x40,
            // 0x40,
            int256(-0x200)
        ];
        int256 x;
        int256 y;
        int128 result;
        int128 expectedResult;
        bool negativeResult;
        for (uint256 index = 0; index < xValues.length; index++) {
            x = xValues[index];
            y = yValues[index];

            // Re-implement logic from lib to derive expected result
            negativeResult = false;
            if (x < 0) {
                x = -x; // We rely on overflow behavior here
                negativeResult = true;
            }
            if (y < 0) {
                y = -y; // We rely on overflow behavior here
                negativeResult = !negativeResult;
            }
            uint128 absoluteResult = Math64x64.divuu(uint256(x), uint256(y));
            if (negativeResult) {
                require(absoluteResult <= 0x80000000000000000000000000000000);
                expectedResult = -int128(absoluteResult); // We rely on overflow behavior here
            } else {
                require(absoluteResult <= 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
                expectedResult = int128(absoluteResult); // We rely on overflow behavior here
            }

            result = Math64x64.divi(x, y);
            assertEq(expectedResult, result);
        }
    }

    function testFailDivByZeroFnDivI() public pure {
        Math64x64.divi(type(int128).max, 0x0);
    }

    function testFuzzFnDivI(int256 x, int256 y) public {
        if (y == 0) return;
        if (x <= type(int128).min) return; // :(
        if (x >= type(int128).max) return; // :(

        int128 expectedResult;
        int128 result;

        bool negativeResult = false;
        if (x < 0) {
            x = -x; // We rely on overflow behavior here
            negativeResult = true;
        }
        if (y < 0) {
            y = -y; // We rely on overflow behavior here
            negativeResult = !negativeResult;
        }
        uint128 absoluteResult = Math64x64.divuu(uint256(x), uint256(y));
        if (negativeResult) {
            if (absoluteResult > 0x80000000000000000000000000000000) return;
            expectedResult = -int128(absoluteResult); // We rely on overflow behavior here
        } else {
            if (absoluteResult > 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF) return;
            expectedResult = int128(absoluteResult); // We rely on overflow behavior here
        }

        result = Math64x64.divi(x, y);

        assertEq(expectedResult, result);
    }

}
