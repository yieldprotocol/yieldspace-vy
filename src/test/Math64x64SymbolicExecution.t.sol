// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.12;

import "ds-test/test.sol";

import "./../contracts/Math64x64.sol";
import "./helpers.sol";

contract Math64x64SymbolicExecution is DSTest {
    function prove_fromInt_Math64x64(int256 from) public {
        if (from < -0x8000000000000000 || from > 0x7FFFFFFFFFFFFFFF) return;

        int128 result = Math64x64.fromInt(from);

        // Re-implement logic from lib to derive expected result
        int128 expectedResult = int128(from << 64);
        assertEq(result, expectedResult);
    }

    function prove_toInt_Math64x64(int256 to) public {
        if (to > type(int128).max || to < type(int128).min) return;
        int64 result = Math64x64.toInt(int128(to));

        // // Re-implement logic from lib to derive expected result
        int64 expectedResult = int64(to >> 64);
        assertEq(result, expectedResult);
    }

    function prove_fromUInt_Math64x64(uint256 from) public {
        if (from > 0x7FFFFFFFFFFFFFFF) return;

        int128 result = Math64x64.fromUInt(from);

        // Re-implement logic from lib to derive expected result
        int128 expectedResult = int128(uint128(from << 64));

        assertEq(expectedResult, result);
    }

    function prove_toUInt_Math64x64(int256 passedIn) public {
        if (passedIn < 0x0) return;
        if (passedIn > int256(0x7FFFFFFFFFFFFFFF)) return;
        int128 to = int128(passedIn);
        int64 result = Math64x64.toInt(to);

        // Re-implement logic from lib to derive expected result
        int128 expectedResult = int64(to >> 64);
        assertEq(expectedResult, result);

        // Property Testing
        // fn(x) < fn(x + 1)
        if (to < to + 1) {
            // skips overflow
            require(Math64x64.toInt(to + 1) >= result);
        }

        // abs(fn(x)) < abs(x)
        require(abs(result) <= abs(to));
    }

    function prove_from128x128_Math64x64(int256 x) public {
        int256 expectedResult256 = x >> 64;
        if (
            expectedResult256 < type(int128).min ||
            expectedResult256 > type(int128).max
        ) return;
        int128 expectedResult = int128(expectedResult256);
        int128 result = Math64x64.from128x128(x);
        assertEq(expectedResult, result);
    }

    function prove_to128x128_Math64x64(int256 passedIn) public {
        if (passedIn > type(int128).max || passedIn < type(int128).min) return;
        int128 to = int128(passedIn);

        int256 result = Math64x64.to128x128(to);

        // // Re-implement logic from lib to derive expected result
        int256 expectedResult = int256(to) << 64;

        assertEq(expectedResult, result);
    }

    function prove_add_Math64x64(int256 passedInX, int256 passedInY) public {
        if (passedInX > type(int128).max || passedInY > type(int128).max)
            return;
        if (passedInX < type(int128).min || passedInY < type(int128).min)
            return;
        int128 x = int128(passedInX);
        int128 y = int128(passedInY);

        // Re-implement logic from lib to derive expected result
        int256 expectedResult;
        unchecked {
            expectedResult = int256(x) + y;
        }
        if (
            expectedResult > type(int128).max ||
            expectedResult < type(int128).min
        ) return;

        int256 result = Math64x64.add(x, y);
        assertEq(expectedResult, result);
    }

    function prove_sub_Math64x64(int256 passedInX, int256 passedInY) public {
        if (passedInX > type(int128).max || passedInY > type(int128).max)
            return;
        if (passedInX < type(int128).min || passedInY < type(int128).min)
            return;
        int128 x = int128(passedInX);
        int128 y = int128(passedInY);

        // Re-implement logic from lib to derive expected result
        int256 expectedResult;
        unchecked {
            expectedResult = int256(x) - y;
        }
        if (
            expectedResult > type(int128).max ||
            expectedResult < type(int128).min
        ) return;

        int256 result = Math64x64.sub(x, y);
        assertEq(expectedResult, result);
    }

    // NOTE: This takes 5 minutes to run locally
    // function prove_mul_Math64x64(int256 passedInX, int256 passedInY) public {
    //     if (passedInX > type(int128).max || passedInY > type(int128).max) return;
    //     if (passedInX < type(int128).min || passedInY < type(int128).min) return;
    //     int128 x = int128(passedInX);
    //     int128 y = int128(passedInY);

    //     // Re-implement logic from lib to derive expected result
    //     int256 expectedResult;
    //     unchecked {
    //         expectedResult = int256(x) * y >> 64;
    //     }
    //     if (expectedResult > type(int128).max || expectedResult < type(int128).min) return;

    //     int256 result = Math64x64.mul(x, y);
    //     assertEq(expectedResult, result);
    // }

    //NOTE: function Math64x64.muli is too complex to test via symbolic execution

    function prove_div_Math64x64(int256 passedInX, int256 passedInY) public {
        if (passedInY == 0) return;
        if (passedInX > type(int128).max || passedInY > type(int128).max)
            return;
        if (passedInX < type(int128).min || passedInY < type(int128).min)
            return;

        int128 x = int128(passedInX);
        int128 y = int128(passedInY);

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

    //NOTE: function Math64x64.divi is too complex to test via symbolic execution

    function prove_neg_Math64x64(int256 x) public {
        if (x > type(int128).max || x <= type(int128).min) return;
        assertEq(Math64x64.neg(int128(x)), -x);
    }

    function prove_abs_Math64x64(int256 x) public {
        if (x > type(int128).max || x <= type(int128).min) return;
        assertEq(Math64x64.abs(int128(x)), abs(x));
    }

    function prove_inv_Math64x64(int256 passedInX) public {
        if (passedInX > type(int128).max || passedInX <= type(int128).min)
            return;
        if (passedInX == 0) return;
        int128 x = int128(passedInX);

        int256 expectedResult = int256(0x100000000000000000000000000000000) / x;
        if (
            expectedResult > type(int128).max ||
            expectedResult < type(int128).min
        ) return;

        assertEq(Math64x64.inv(int128(x)), int128(expectedResult));
    }

    function prove_avg_Math64x64(int256 passedInX, int256 passedInY) public {
        if (passedInX > type(int128).max || passedInY > type(int128).max)
            return;
        if (passedInX < type(int128).min || passedInY < type(int128).min)
            return;
        int128 x = int128(passedInX);
        int128 y = int128(passedInY);

        int128 result = Math64x64.avg(x, y);

        int128 expectedResult = int128((int256(x) + int256(y)) >> 1);

        assertEq(expectedResult, result);
    }

    //NOTE: function Math64x64.gavg is too complex to test via symbolic execution

    //NOTE: function Math64x64.sqrt is too complex to test via symbolic execution

    //NOTE: function Math64x64.log_2 is too complex to test via symbolic execution

    //NOTE: function Math64x64.ln is too complex to test via symbolic execution
}
