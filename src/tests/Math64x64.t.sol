// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.6;

import "ds-test/test.sol";

import "./../contracts/Math64x64.sol";

contract Math64x64Test is DSTest {
    Math64x64 m;

    function setUp() public {
        m = new Math64x64();
    }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }
}
