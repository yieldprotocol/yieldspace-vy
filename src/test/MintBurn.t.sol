// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.11;

import "forge-std/stdlib.sol";
import {Vm} from "forge-std/Vm.sol";
import {console} from "forge-std/console.sol";

import "./shared/Utils.sol";
import "./shared/Constants.sol";
import {Pool} from "../contracts/Pool.sol";
import {TestCore} from "./shared/TestCore.sol";
import {ERC20User} from "./users/ERC20User.sol";
import {Exp64x64} from "../contracts/Exp64x64.sol";
import {FYTokenMock} from "./mocks/FYTokenMock.sol";
import {YVTokenMock} from "./mocks/YVTokenMock.sol";
import {Math64x64} from "../contracts/Math64x64.sol";
import {YieldMath} from "../contracts/YieldMath.sol";

abstract contract ZeroState is TestCore {
    using Math64x64 for int128;
    using Math64x64 for uint128;
    using Math64x64 for int256;
    using Math64x64 for uint256;
    using Exp64x64 for uint128;

    uint256 public constant aliceYVInitialBalance = 1000 * 1e18;
    uint256 public constant bobYVInitialBalance = 2_000_000 * 1e18;


    uint256 public constant initialFYTokens = 0;
    uint256 public constant initialBase = 0;

    // setup tokenlist for params to ERC20User because passing arrays in Solidity is weird
    address[] public tokenList = new address[](2); // !!!

    function setUp() public virtual {
        ts = ONE.div(uint256(25 * 365 * 24 * 60 * 60 * 10).fromUInt());
        // setup mock tokens
        base = new YVTokenMock("Yearn Vault Dai", BASE_SYMBOL, 18, address(0));
        base.setPrice(cNumerator * 1e18 / cDenominator);
        fyToken = new FYTokenMock("fyToken yvDai maturity 1", FY_SYMBOL, address(base), maturity);
        fyToken.name();
        fyToken.symbol();

        // setup pool
        pool = new Pool(address(base), address(fyToken), ts, g1, g2, mu);

        // assign tokenList params
        tokenList[0] = address(base);
        tokenList[1] = address(fyToken);

        // setup users
        alice = new ERC20User("alice", tokenList);
        alice.setBalance(base.symbol(), aliceYVInitialBalance);
        bob = new ERC20User("bob", tokenList);
        bob.setBalance(base.symbol(), bobYVInitialBalance);
    }
}

abstract contract WithLiquidity is ZeroState {
    // used in 2 test suites __WithLiquidity
    function setUp() public override {
        super.setUp();
        base.mint(address(pool), INITIAL_BASE);

        pool.mint(address(alice), address(bob), 0, MAX);
        uint256 additionalFYToken = INITIAL_BASE / 9;

        // Skew the balances without using trading functions
        fyToken.mint(address(pool), additionalFYToken);

        pool.sync();
    }
}

contract Mint__ZeroState is ZeroState {
    function testUnit_mint1() public {
        console.log("adds initial liquidity");

        vm.startPrank(address(bob));
        base.transfer(address(pool), INITIAL_BASE);
        vm.expectEmit(true, true, true, true);
        emit Liquidity(
            maturity,
            address(bob),
            address(bob),
            address(0),
            int256(-1 * int256(INITIAL_BASE)),
            int256(0),
            int256(INITIAL_BASE)
        );
        pool.mint(address(bob), address(bob), 0, MAX);

        vm.stopPrank();

        require(pool.balanceOf(address(bob)) == INITIAL_BASE);
        (uint112 baseBal, uint112 fyTokenBal, uint32 unused) = pool.getCache();
        require(baseBal == pool.getBaseBalance());
        require(fyTokenBal == pool.getFYTokenBalance());
    }

    function testUnit_mint2() public {
        console.log("adds liquidity with zero fyToken");
        base.mint(address(pool), INITIAL_BASE);

        vm.startPrank(address(alice));
        pool.mint(address(0), address(0), 0, MAX);

        // After initializing, donate base and sync to simulate having reached zero fyToken through trading
        base.mint(address(pool), INITIAL_BASE);
        pool.sync();

        base.mint(address(pool), INITIAL_BASE);
        pool.mint(address(bob), address(bob), 0, MAX);

        vm.stopPrank();

        require(pool.balanceOf(address(bob)) == INITIAL_BASE / 2);
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

        vm.prank(address(alice));
        pool.sync();

        (uint112 baseBal, uint112 fyTokenBal, uint32 unused1) = pool.getCache();
        require(baseBal == pool.getBaseBalance());
        require(fyTokenBal == pool.getFYTokenBalance());
    }
}

contract Mint__WithLiquidity is WithLiquidity {
    function testUnit_mint4() public {
        console.log("mints liquidity tokens, returning base surplus");
        uint256 fyTokenIn = WAD;
        uint256 expectedMint = (pool.totalSupply() / (fyToken.balanceOf(address(pool)))) * 1e18;
        uint256 expectedBaseIn = (base.balanceOf(address(pool)) * expectedMint) / pool.totalSupply();

        uint256 baseTokensBefore = base.balanceOf(address(bob));
        uint256 poolTokensBefore = pool.balanceOf(address(bob));

        base.mint(address(pool), expectedBaseIn + 1e18); // send an extra wad of base
        fyToken.mint(address(pool), fyTokenIn);

        vm.prank(address(alice));
        pool.mint(address(bob), address(bob), 0, MAX);

        uint256 minted = pool.balanceOf(address(bob)) - poolTokensBefore;

        almostEqual(minted, expectedMint, fyTokenIn / 10000);
        almostEqual(base.balanceOf(address(bob)), WAD + bobYVInitialBalance, fyTokenIn / 10000);

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

contract Burn__WithLiquidity is WithLiquidity {
    function testUnit_burn1() public {
        console.log("burns liquidity tokens");
        uint256 baseBalance = base.balanceOf(address(pool));
        uint256 fyTokenBalance = fyToken.balanceOf(address(pool));
        uint256 poolSup = pool.totalSupply();
        uint256 lpTokensIn = WAD;

        ERC20User charlie = new ERC20User("charlie", tokenList);

        uint256 expectedBaseOut = (lpTokensIn * baseBalance) / poolSup;
        uint256 expectedFYTokenOut = (lpTokensIn * fyTokenBalance) / poolSup;

        // alice transfers in lp tokens then burns them
        vm.startPrank(address(alice));
        pool.transfer(address(pool), lpTokensIn);

        vm.expectEmit(true, true, true, true);
        emit Liquidity(
            maturity,
            address(alice),
            address(bob),
            address(charlie),
            int256(expectedBaseOut),
            int256(expectedFYTokenOut),
            -int256(lpTokensIn)
        );
        pool.burn(address(bob), address(charlie), 0, MAX);

        vm.stopPrank();

        uint256 baseOut = baseBalance - base.balanceOf(address(pool));
        uint256 fyTokenOut = fyTokenBalance - fyToken.balanceOf(address(pool));
        almostEqual(baseOut, expectedBaseOut, baseOut / 10000);
        almostEqual(fyTokenOut, expectedFYTokenOut, fyTokenOut / 10000);

        (uint112 baseBal, uint112 fyTokenBal, uint32 unused) = pool.getCache();
        require(baseBal == pool.getBaseBalance());
        require(fyTokenBal == pool.getFYTokenBalance());
        require(base.balanceOf(address(bob)) - bobYVInitialBalance == baseOut);
        require(fyToken.balanceOf(address(charlie)) == fyTokenOut);
    }
}
