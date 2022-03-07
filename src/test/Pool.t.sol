// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.11;

import "ds-test/test.sol";


import {Math64x64} from "../contracts/Math64x64.sol";
import {Exp64x64} from "../contracts/Exp64x64.sol";

import {Pool} from "src/contracts/Pool.sol";
import {FYTokenMock} from "./mocks/FYTokenMock.sol";
import {YVTokenMock} from "./mocks/YVTokenMock.sol";
import {YVTokenMock} from "./mocks/YVTokenMock.sol";
import {PoolUser} from "./users/PoolUser.sol";

uint256 constant THREE_MONTHS = uint256(3) * 30 * 24 * 60 * 60;
int128 constant ONE = 0x10000000000000000; // In 64.64

contract PoolTest is DSTest {
    using Math64x64 for int128;
    using Math64x64 for uint128;
    using Math64x64 for int256;
    using Math64x64 for uint256;
    using Exp64x64 for uint128;


    YVTokenMock public yvToken;
    FYTokenMock public fyToken;
    Pool public pool;
    uint256 public initialBase = 1_100_000 * 1e18;
    uint256 public initialFYTokens = 1_500_000 * 1e18;
    PoolUser public user1;
    PoolUser public user2;
    uint256 user1YVInitialBalance = 1000 * 1e18;
    uint256 user2YVInitialBalance = 2_000_000 * 1e18;

    int128 public g1 = int128(95) * 1e18 / 100;
    int128 public g2 = int128(100) * 1e18 / 95;
    int128 public ts;
    uint32 public maturity;

    function setUp() external {
        maturity = uint32(block.timestamp + THREE_MONTHS);
        uint256 invK = 25 * 365 * 24 * 60 * 60 * 10;
        ts = ONE.div(invK.fromUInt());

        // setup mock tokens
        yvToken = new YVTokenMock("Yearn Vault Dai", "yvDai", 18, address(0));
        fyToken = new FYTokenMock("fyToken yvDai maturity 1", "fyYvDai1", address(yvToken), maturity);
        fyToken.name();
        fyToken.symbol();

        // setup pool
        pool = new Pool(
            address(yvToken),
            address(fyToken),
            ts,
            g1,
            g2
        );

        // setup users
        user1 = new PoolUser(address(yvToken), address(fyToken));
        user1.setYVTokenBalance(user1YVInitialBalance);

        user2 = new PoolUser(address(yvToken), address(fyToken));
        user2.setYVTokenBalance(user2YVInitialBalance);

    }

    function testUnit_mint1() public {
        // it('adds initial liquidity')
        yvToken.pricePerShare();
        fyToken.totalSupply();
        user2.transferYVToken(address(pool), initialBase);
        pool.mint(address(user2), address(user2), 0, type(uint256).max);
        // check event ^^ TODO:!!!!!!!!!!!!!!!!!!!!!
        require(pool.balanceOf(address(user2)) == initialBase);
        (uint112 baseBal, uint112 fyTokenBal, uint32 unused) = pool.getCache();
        require (baseBal == pool.getBaseBalance());
        require (fyTokenBal == pool.getFYTokenBalance());
    }

    function testUnit_mint2(uint256 x) public {
        require(x != 69);
        // it('adds liquidity with zero fyToken')
        yvToken.mint(address(pool), initialBase);
        pool.mint(address(0), address(0), 0, type(uint256).max);

        // After initializing, donate base and sync to simulate having reached zero fyToken through trading
        yvToken.mint(address(pool), initialBase);
        pool.sync();

        yvToken.mint(address(pool), initialBase);
        pool.mint(address(user2), address(user2), 0, type(uint256).max);

        require(pool.balanceOf(address(user2)) == initialBase / 2);

        (uint112 baseBal, uint112 fyTokenBal, uint32 unused) = pool.getCache();
        require (baseBal == pool.getBaseBalance());
        require (fyTokenBal == pool.getFYTokenBalance());
   }
    function testUnit_mint3() public {
        // it('syncs balances after donations')
        yvToken.mint(address(pool), initialBase);
        fyToken.mint(address(pool), initialBase / 9);

        pool.sync(); // TODO: check event

        (uint112 baseBal, uint112 fyTokenBal, uint32 unused) = pool.getCache();
        require (baseBal == pool.getBaseBalance());
        require (fyTokenBal == pool.getFYTokenBalance());

   }

}