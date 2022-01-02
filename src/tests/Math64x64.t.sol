// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.11;

import "ds-test/test.sol";

import "./../contracts/Math64x64.sol";
contract Math64x64Test is DSTest {

/****************************************************************
    UNIT TESTS
*****************************************************************/
/****************************************************************
    SYMBOLIC EXECUTION
*****************************************************************/
    function proveFromInt(int256 from) public {
        from = from % (0x8000000000000000 + 0x7FFFFFFFFFFFFFFF + 1) - 0x8000000000000000;

        int128 result = Math64x64.fromInt(from);

        // // 1. Re-implement logic from lib to derive expected result
        // int128 expectedResult = int128(from << 64);
        // assertEq(result, expectedResult);

        // 2. Start with result and work backward to derive expected parameter
        int256 expectedFrom = int256(result) >> 64;
        assertEq(from, expectedFrom);

        // // 3. Property Testing
        // // fn(x + 1) > fn(x)
        // if (from + 1 <= 0x7FFFFFFFFFFFFFFF) { // skip overflow
        //     assertTrue(Math64x64.fromInt(from + 1) > result);
        // }
        // // fn(x) >= x
        // assertTrue(result >= from);
    }
    // function proveFromUInt(uint256 from) public {
    //     from = from % (0x7FFFFFFFFFFFFFFF + 1);

    //     int128 result = Math64x64.fromUInt(from);

    //     // 1. Re-implement logic from lib to derive expected result
    //     int128 expectedResult = int128(uint128(from << 64));
    //     assertEq(result, expectedResult);

    //     // 2. Start with result and work backward to derive expected parameter
    //     uint256 expectedFrom = uint256(uint128(result >> 64));
    //     assertEq(from, expectedFrom);

    //     // 3. Property Testing
    //     // fn(x + 1) > fn(x)
    //     if (from + 1 <= 0x7FFFFFFFFFFFFFFF) { // skip overflow
    //         assertTrue(Math64x64.fromUInt(from + 1) > result);
    //     }
    //     // fn(x) >= x
    //     assertTrue(uint256(uint128(result)) >= from);
    }



/****************************************************************
    FUZZY TESTING
*****************************************************************/

}
