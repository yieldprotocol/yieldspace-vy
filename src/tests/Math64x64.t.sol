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

        Test name type prefixes:
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
        int256 from = coerce256IntTo128(passedIn);

        int128 result = Math64x64.fromInt(from);

        // Work backward to derive expected param
        int64 expectedFrom = Math64x64.toInt(result);
        assertEq(from, int256(expectedFrom));

        // Property Testing

        // fn(x) < fn(x + 1)
        if (from + 1 <= 0x7FFFFFFFFFFFFFFF) {
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
        if (to < to + 1) {
            // skips overflow
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
        if (from + 1 <= 0x7FFFFFFFFFFFFFFF) {
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
        if (to < to + 1) {
            // skips overflow
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
        if (to < to + 1) {
            // skips overflow
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
}
