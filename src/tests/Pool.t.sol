// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.11;

import "ds-test/test.sol";

import {Pool} from "src/contracts/Pool.sol";
import {FYTokenMock} from "../tests/mocks/FYTokenMock.sol";
import {YVTokenMock} from "../tests/mocks/YVTokenMock.sol";


contract PoolTest is DSTest {

    Pool pool;
    YVTokenMock YVToken;
    FYTokenMock fyToken;
    int128 g1 = int128(95) * 1e18 / 100;
    int128 g2 = int128(100) * 1e18 / 95;

    uint256 public constant THREE_MONTHS = uint256(3) * 30 * 24 * 60 * 60;


    function setUp() external {
        YVToken = new YVTokenMock("Yearn Vault Dai", "yvDai", 18, address(0));
        fyToken = new FYTokenMock("fyToken yvDai maturity 1", "fyYvDai1", address(YVToken), uint32(1));
        pool = new Pool(
            address(fyToken),
            address(YVToken),
            int128(uint128(block.timestamp + THREE_MONTHS)),
            g1,
            g2
        );
    }

    function testUnit_mint() public {
        // 'adds initial liquidity'

    }

}