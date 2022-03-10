// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.11;

import "ds-test/test.sol";


import {console} from "forge-std/console.sol";

import {YieldMath} from "../contracts/YieldMath.sol";
import {Math64x64} from "../contracts/Math64x64.sol";
import {Exp64x64} from "../contracts/Exp64x64.sol";
import {Pool} from "src/contracts/Pool.sol";
import {FYTokenMock} from "./mocks/FYTokenMock.sol";
import {YVTokenMock} from "./mocks/YVTokenMock.sol";
import {PoolUser} from "./users/PoolUser.sol";


// constants
uint256 constant WAD = 1e18;
uint256 constant MAX = type(uint256).max;
uint256 constant THREE_MONTHS = uint256(3) * 30 * 24 * 60 * 60;


int128 constant ONE = 0x10000000000000000; // In 64.64
uint256 constant INITIAL_BASE = 1_000_000 * 1e18;
uint256 constant INITIAL_FY_TOKENS = 1_000_000 * 1e18;
// uint256 constant INITIAL_BASE = 1_100_000 * 1e18;
// uint256 constant INITIAL_FY_TOKENS = 1_500_000 * 1e18;
int128 constant G1 = int128(95) * 1e18 / 100;
int128 constant G2 = int128(100) * 1e18 / 95;

// contract base
abstract contract MintTestCore is DSTest {
    using Math64x64 for int128;
    using Math64x64 for uint128;
    using Math64x64 for int256;
    using Math64x64 for uint256;
    using Exp64x64 for uint128;

    YVTokenMock public base;
    FYTokenMock public fyToken;
    Pool public pool;
    // uint256 public INITIAL_BASE = 1_100_000 * 1e18;
    // uint256 public INITIAL_FY_TOKENS = 1_500_000 * 1e18;
    address public user1;
    address public user2;
    uint256 user1YVInitialBalance = 1000 * 1e18;
    uint256 user2YVInitialBalance = 2_000_000 * 1e18;

    uint32 public maturity = uint32(block.timestamp + THREE_MONTHS);

    int128 public ts;
    function initialSetup() public {
        ts = ONE.div(uint256(25 * 365 * 24 * 60 * 60 * 10).fromUInt());
        // setup mock tokens
        base = new YVTokenMock("Yearn Vault Dai", "yvDai", 18, address(0));
        base.setPrice(109 * 1e16);
        fyToken = new FYTokenMock("fyToken yvDai maturity 1", "fyYVDai1", address(base), maturity);
        fyToken.name();
        fyToken.symbol();

        // setup pool
        pool = new Pool(
            address(base),
            address(fyToken),
            ts,
            G1,
            G2
        );

        // setup users
        PoolUser newUser1 = new PoolUser(address(base), address(fyToken));
        PoolUser newUser2 = new PoolUser(address(base), address(fyToken));
        user1 = address(newUser1);
        user2 = address(newUser2);

    }

    function almostEqual(uint256 x, uint256 y, uint256 p) public view {
        uint256 diff = x > y ? x - y : y - x;
        if (diff / p > 0) {
            console.log(x);
            console.log("is not almost equal to");
            console.log(y);
            console.log("with  p of:");
            console.log(p);
            revert();
        }
    }
}

contract PoolTest__Mint__Base is MintTestCore {
    function setUp() external {
        initialSetup();
        PoolUser(user1).setYVTokenBalance(user1YVInitialBalance);
        PoolUser(user2).setYVTokenBalance(user2YVInitialBalance);
    }

    function testUnit_mint1() public {
        console.log("adds initial liquidity");
        PoolUser(user2).transferYVToken(address(pool), INITIAL_BASE);
        pool.mint(user2, user2, 0, MAX);
        // check event ^^ TODO:!!!!!!!!!!!!!!!!!!!!!
        require(pool.balanceOf(user2) == INITIAL_BASE);
        (uint112 baseBal, uint112 fyTokenBal, uint32 unused) = pool.getCache();
        require (baseBal == pool.getBaseBalance());
        require (fyTokenBal == pool.getFYTokenBalance());
                                                                                                                                                                                                                                                    }

    function testUnit_mint2() public {
        console.log("adds liquidity with zero fyToken");
        base.mint(address(pool), INITIAL_BASE);
        pool.mint(address(0), address(0), 0, MAX);

        // After initializing, donate base and sync to simulate having reached zero fyToken through trading
        base.mint(address(pool), INITIAL_BASE);
        pool.sync();

        base.mint(address(pool), INITIAL_BASE);
        pool.mint(user2, user2, 0, MAX);

        require(pool.balanceOf(user2) == INITIAL_BASE / 2);

        (uint112 baseBal, uint112 fyTokenBal, uint32 unused) = pool.getCache();
        require (baseBal == pool.getBaseBalance());
        require (fyTokenBal == pool.getFYTokenBalance());
   }
    function testUnit_mint3() public {
        console.log("syncs balances after donations");
        base.mint(address(pool), INITIAL_BASE);
        fyToken.mint(address(pool), INITIAL_BASE / 9);

        pool.sync(); // TODO: check event

        (uint112 baseBal, uint112 fyTokenBal, uint32 unused) = pool.getCache();
        require (baseBal == pool.getBaseBalance());
        require (fyTokenBal == pool.getFYTokenBalance());

   }

}

contract PoolTest__Mint__WithLiquidity is MintTestCore {

    function setUp() external {
        initialSetup();

        base.mint(address(pool), INITIAL_BASE);
        pool.mint(user1, user2, 0, MAX);

        uint256 additionalFYToken = INITIAL_BASE / 9;
        // Skew the balances without using trading functions
        fyToken.mint(address(pool), additionalFYToken);
        pool.sync();
    }

    function testUnit_mint4() public {
        console.log("mints liquidity tokens, returning base surplus");
        uint256 fyTokenIn = WAD;
        uint256 expectedMint = (pool.totalSupply() / (fyToken.balanceOf(address(pool)))) * 1e18;
        uint256 expectedBaseIn = (base.balanceOf(address(pool)) * expectedMint) / pool.totalSupply();

        uint256 baseTokensBefore = base.balanceOf(user2);
        uint256 poolTokensBefore = pool.balanceOf(user2);

        base.mint(address(pool), expectedBaseIn + 1e18); // send an extra wad of base
        fyToken.mint(address(pool), fyTokenIn);
        pool.mint(user2, user2, 0, MAX);

        uint256 minted   = pool.balanceOf(user2) - poolTokensBefore;


        almostEqual(minted, expectedMint, fyTokenIn / 10000);
        almostEqual(base.balanceOf(user2), WAD, fyTokenIn / 10000);

        (uint112 baseBal, uint112 fyTokenBal, uint32 unused) = pool.getCache();

        require(baseBal == pool.getBaseBalance());
        require(fyTokenBal == pool.getFYTokenBalance());

    }

    // NOTE: consider skipping this test because there's a whole test suite for mintWithBase
    // function testUnit_mint5() public {
    //     console.log("mints liquidity tokens with base only");
    //     uint256 fyTokenToBuy = WAD / 1000;

    //     uint256 expectedMint = (pool.totalSupply() / (fyToken.balanceOf(address(pool)))) * 1e18;
    //     uint256 expectedBaseIn = (base.balanceOf(address(pool)) * expectedMint) / pool.totalSupply();

    //     uint256 poolTokensBefore = pool.balanceOf(user2);
    //     uint256 poolSupplyBefore = pool.totalSupply();
    //     (uint112 baseCachedBefore, uint112 fyTokenCachedBefore, uint32 unused1) = pool.getCache();

    //     base.mint(address(pool), expectedBaseIn);

    //     pool.mintWithBase(user2, user2, fyTokenToBuy, 0, MAX);  // TODO: Check event!!

    //     (uint112 baseCachedAfter, uint112 fyTokenCachedAfter, uint32 unused2) = pool.getCache();

    //     uint112 baseIn = baseCachedAfter - baseCachedBefore;
    //     uint256 minted = pool.balanceOf(user2) - poolTokensBefore;
    //     console.logUint(minted);
    //     console.logUint(expectedMint);
    //     console.logUint(minted / 10000);
    //     almostEqual(minted, expectedMint, minted / 10000);

    //     almostEqual(baseIn, expectedBaseIn, baseIn /10000);
    //     require(baseCachedAfter == baseCachedBefore + baseIn);
    //     require(fyTokenCachedAfter == fyTokenCachedBefore + minted);
    // }


}