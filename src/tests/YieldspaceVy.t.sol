// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.6;

import "ds-test/test.sol";

import "./../contracts/YieldspaceVy.sol";

contract YieldspaceVyTest is DSTest {
    YieldspaceVy vy;

    function setUp() public {
        vy = new YieldspaceVy();
    }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }
}
