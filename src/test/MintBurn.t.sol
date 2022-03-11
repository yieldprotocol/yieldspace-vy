// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.11;

import "ds-test/test.sol";

import {console} from "forge-std/console.sol";
import {Vm} from "forge-std/Vm.sol";

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

uint256 constant INITIAL_BASE = 1_100_000 * 1e18;
uint256 constant INITIAL_FY_TOKENS = 1_500_000 * 1e18;

// 64.64
int128 constant ONE = 0x10000000000000000;
int128 constant G1 = (int128(95) * 1e18) / 100;
int128 constant G2 = (int128(100) * 1e18) / 95;



// contract base
abstract contract MintBurnTestCore is DSTest {
    event Liquidity(
        uint32 maturity,
        address indexed from,
        address indexed to,
        address indexed fyTokenTo,
        int256 bases,
        int256 fyTokens,
        int256 poolTokens
    );

    event Sync(
        uint112 baseCached,
        uint112 fyTokenCached,
        uint256 cumulativeBalancesRatio
    );

    using Math64x64 for int128;
    using Math64x64 for uint128;
    using Math64x64 for int256;
    using Math64x64 for uint256;
    using Exp64x64 for uint128;

    Vm public vm = Vm(HEVM_ADDRESS);
    YVTokenMock public base;
    FYTokenMock public fyToken;
    Pool public pool;
    address public user1;
    address public user2;
    uint256 user1YVInitialBalance = 1000 * 1e18;
    uint256 user2YVInitialBalance = 2_000_000 * 1e18;

    uint32 public maturity = uint32(block.timestamp + THREE_MONTHS);

    int128 public ts;

    function zeroStateSetup() public {
        ts = ONE.div(uint256(25 * 365 * 24 * 60 * 60 * 10).fromUInt());
        // setup mock tokens
        base = new YVTokenMock("Yearn Vault Dai", "yvDai", 18, address(0));
        base.setPrice(109 * 1e16);
        fyToken = new FYTokenMock("fyToken yvDai maturity 1", "fyYVDai1", address(base), maturity);
        fyToken.name();
        fyToken.symbol();

        // setup pool
        pool = new Pool(address(base), address(fyToken), ts, G1, G2);

        // setup users
        PoolUser newUser1 = new PoolUser(address(base), address(fyToken));
        PoolUser newUser2 = new PoolUser(address(base), address(fyToken));
        user1 = address(newUser1);
        vm.label(user1, "user1");
        user2 = address(newUser2);
        vm.label(user2, "user2");
    }

    // used in 2 test suites __WithLiquidity
    function withLiquiditySetup() public {
        base.mint(address(pool), INITIAL_BASE);

        vm.prank(user1);
        pool.mint(user1, user2, 0, MAX);

        uint256 additionalFYToken = INITIAL_BASE / 9;
        // Skew the balances without using trading functions
        fyToken.mint(address(pool), additionalFYToken);

        vm.prank(user1);
        pool.sync();
    }

    function almostEqual(
        uint256 x,
        uint256 y,
        uint256 p
    ) public view {
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

contract ZeroState__Mint is MintBurnTestCore {
    function setUp() external {
        zeroStateSetup();
        PoolUser(user1).setYVTokenBalance(user1YVInitialBalance);
        PoolUser(user2).setYVTokenBalance(user2YVInitialBalance);
    }

    function testUnit_mint1() public {
        console.log("adds initial liquidity");

        vm.startPrank(user2);
        base.transfer(address(pool), INITIAL_BASE);
        vm.expectEmit(true, true, true, true);
        emit Liquidity(maturity, user2, user2, address(0), int256(-1 * int256(INITIAL_BASE)), int256(0), int256(INITIAL_BASE));
        pool.mint(user2, user2, 0, MAX);


        vm.stopPrank();

        require(pool.balanceOf(user2) == INITIAL_BASE);
        (uint112 baseBal, uint112 fyTokenBal, uint32 unused) = pool.getCache();
        require(baseBal == pool.getBaseBalance());
        require(fyTokenBal == pool.getFYTokenBalance());
    }

    function testUnit_mint2() public {
        console.log("adds liquidity with zero fyToken");
        base.mint(address(pool), INITIAL_BASE);

        vm.prank(user1);
        pool.mint(address(0), address(0), 0, MAX);

        // After initializing, donate base and sync to simulate having reached zero fyToken through trading
        base.mint(address(pool), INITIAL_BASE);
        vm.prank(user1);
        pool.sync();

        base.mint(address(pool), INITIAL_BASE);
        vm.prank(user1);
        pool.mint(user2, user2, 0, MAX);

        require(pool.balanceOf(user2) == INITIAL_BASE / 2);

        (uint112 baseBal, uint112 fyTokenBal, uint32 unused) = pool.getCache();
        require(baseBal == pool.getBaseBalance());
        require(fyTokenBal == pool.getFYTokenBalance());
    }

    function testUnit_mint3() public {
        console.log("syncs balances after donations");
        base.mint(address(pool), INITIAL_BASE);
        fyToken.mint(address(pool), INITIAL_BASE / 9);

        vm.expectEmit(false, false, false, true);
        emit Sync(uint112(INITIAL_BASE), uint112(INITIAL_BASE / 9), 0);
        vm.prank(user1);
        pool.sync();

        (uint112 baseBal, uint112 fyTokenBal, uint32 unused1) = pool.getCache();
        require(baseBal == pool.getBaseBalance());
        require(fyTokenBal == pool.getFYTokenBalance());
    }
}

contract Mint__WithLiquidity is MintBurnTestCore {
    function setUp() external {
        zeroStateSetup();
        withLiquiditySetup();
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

        vm.prank(user1);
        pool.mint(user2, user2, 0, MAX);

        uint256 minted = pool.balanceOf(user2) - poolTokensBefore;

        almostEqual(minted, expectedMint, fyTokenIn / 10000);
        almostEqual(base.balanceOf(user2), WAD, fyTokenIn / 10000);

        (uint112 baseBal, uint112 fyTokenBal, uint32 unused) = pool.getCache();

        require(baseBal == pool.getBaseBalance());
        require(fyTokenBal == pool.getFYTokenBalance());
    }

    // TODO: move to 034
    // function testUnit_mintX() public {
    //     console.log("mints liquidity tokens with base only");

    // TODO: include this in mintForBase tests along with maxRatio in 034
    // function testUnit_mint5() public {
    //     console.log("doesn't mint if ratio drops below minRatio");

    // TODO: move last 2 tests in 031 (burnForBase min/maxRatio tests) to 034
}

contract Burn__WithLiquidity is MintBurnTestCore {
    function setUp() external {
        zeroStateSetup();
        withLiquiditySetup();
    }

    function testUnit_burn1() public {
        console.log("burns liquidity tokens");
        uint256 baseBalance = base.balanceOf(address(pool));
        uint256 fyTokenBalance = fyToken.balanceOf(address(pool));
        uint256 poolSup = pool.totalSupply();
        uint256 lpTokensIn = WAD;

        PoolUser user3 = new PoolUser(address(base), address(fyToken));
        vm.label(address(user3), "user3");

        uint256 expectedBaseOut = (lpTokensIn * baseBalance) / poolSup;
        uint256 expectedFYTokenOut = (lpTokensIn * fyTokenBalance) / poolSup;

        // user 1 transfers in lp tokens then burns them
        vm.startPrank(user1);
        pool.transfer(address(pool), lpTokensIn);

        vm.expectEmit(true, true, true, true);
        emit Liquidity(maturity, user1, user2, address(user3), int256(expectedBaseOut), int256(expectedFYTokenOut), -int256(lpTokensIn));
        pool.burn(user2, address(user3), 0, MAX);
        vm.stopPrank();

        uint256 baseOut = baseBalance - base.balanceOf(address(pool));
        uint256 fyTokenOut = fyTokenBalance - fyToken.balanceOf(address(pool));
        almostEqual(baseOut, expectedBaseOut, baseOut / 10000);
        almostEqual(fyTokenOut, expectedFYTokenOut, fyTokenOut / 10000);

        (uint112 baseBal, uint112 fyTokenBal, uint32 unused) = pool.getCache();
        require(baseBal == pool.getBaseBalance());
        require(fyTokenBal == pool.getFYTokenBalance());
        require(baseBal == pool.getBaseBalance());
        require(fyTokenBal == pool.getFYTokenBalance());
        require(base.balanceOf(user2) == baseOut);
        require(fyToken.balanceOf(address(user3)) == fyTokenOut);
    }
}
