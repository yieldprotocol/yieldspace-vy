// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.13;

/*
  __     ___      _     _
  \ \   / (_)    | |   | | ████████╗███████╗███████╗████████╗███████╗
   \ \_/ / _  ___| | __| | ╚══██╔══╝██╔════╝██╔════╝╚══██╔══╝██╔════╝
    \   / | |/ _ \ |/ _` |    ██║   █████╗  ███████╗   ██║   ███████╗
     | |  | |  __/ | (_| |    ██║   ██╔══╝  ╚════██║   ██║   ╚════██║
     |_|  |_|\___|_|\__,_|    ██║   ███████╗███████║   ██║   ███████║
      yieldprotocol.com       ╚═╝   ╚══════╝╚══════╝   ╚═╝   ╚══════╝

*/

import "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {console} from "forge-std/console.sol";

import {Exp64x64} from "../contracts/Exp64x64.sol";
import {Math64x64} from "../contracts/Math64x64.sol";
import {YieldMath} from "../contracts/YieldMath.sol";

import "./shared/Utils.sol";
import "./shared/Constants.sol";
import {Pool} from "../contracts/Pool/Pool.sol";
import {FYTokenMock} from "./mocks/FYTokenMock.sol";
import {YVTokenMock} from "./mocks/YVTokenMock.sol";
import {ZeroStateUSDC} from "./shared/ZeroState.sol";


abstract contract WithLiquidity is ZeroStateUSDC {
    function setUp() public virtual override {
        super.setUp();
        base.mint(address(pool), initialBase);
        pool.mint(address(0), address(0), 0, MAX);
        base.setPrice((cNumerator * (10**base.decimals())) / cDenominator);
        fyToken.mint(address(pool), initialFYTokens);
        pool.sync();

    }
}

abstract contract WithExtraFYTokenUSDC is WithLiquidity {
    using Math64x64 for int128;
    using Math64x64 for uint128;
    using Math64x64 for int256;
    using Math64x64 for uint256;
    using Exp64x64 for uint128;

    function setUp() public virtual override {
        super.setUp();
        uint256 additionalFYToken = 30 * WAD;
        fyToken.mint(address(this), additionalFYToken);
        vm.prank(alice);
        pool.sellFYToken(address(this), 0);
    }
}

contract TradeUSDC__WithLiquidity is WithLiquidity {
    using Math64x64 for uint256;
    using Math64x64 for int128;

    function testUnit_tradeUSDC01() public {
        console.log("sells a certain amount of fyToken for base");
        uint256 fyTokenIn = 25_000 * 1e6;

        fyToken.mint(address(pool), fyTokenIn);

        vm.prank(alice);
        pool.sellFYToken(bob, 0);

        (uint112 baseBal, uint112 fyTokenBal,) = pool.getCache();
        require(baseBal == pool.getBaseBalance());
        require(fyTokenBal == pool.getFYTokenBalance());
    }

    function testUnit_tradeUSDC02() public {
        console.log("does not sell fyToken beyond slippage");
        uint256 fyTokenIn = 1e6;
        fyToken.mint(address(pool), fyTokenIn);
        vm.expectRevert(bytes("Pool: Not enough base obtained"));
        pool.sellFYToken(bob, type(uint128).max);
    }

    function testUnit_tradeUSDC03() public {
        console.log("donates base and sells fyToken");

        uint256 baseDonation = 1e6;
        uint256 fyTokenIn = 1e6;

        base.mint(address(pool), baseDonation);
        fyToken.mint(address(pool), fyTokenIn);

        vm.prank(bob);
        pool.sellFYToken(bob, 0);

        (uint112 baseBal, uint112 fyTokenBal,) = pool.getCache();
        require(baseBal == pool.getBaseBalance());
        require(fyTokenBal == pool.getFYTokenBalance());
    }

    function testUnit_tradeUSDC04() public {
        console.log("buys a certain amount base for fyToken");
        (, uint112 fyTokenBalBefore,) = pool.getCache();
        // (uint112 baseBalBefore, uint112 fyTokenBalBefore,) = pool.getCache();

        uint256 userBaseBefore = base.balanceOf(bob);
        uint128 baseOut = uint128(1000 * 1e6);

        uint128 virtFYTokenBal = uint128(fyToken.balanceOf(address(pool)) + pool.totalSupply());
        uint128 sharesReserves = uint128(base.balanceOf(address(pool)));
        int128 c_ = (base.pricePerShare().fromUInt()).div(uint256(1e6).fromUInt());

        fyToken.mint(address(pool), initialFYTokens); // send some tokens to the pool

        uint256 expectedFYTokenIn = YieldMath.fyTokenInForSharesOut(
            sharesReserves * 1e12,
            virtFYTokenBal * 1e12,
            baseOut * 1e12,
            maturity - uint32(block.timestamp),
            k,
            g2,
            c_,
            mu
        ) / 1e12;

        vm.prank(bob);
        pool.buyBase(bob, uint128(baseOut), type(uint128).max);

        (, uint112 fyTokenBal,) = pool.getCache();
        uint256 fyTokenIn = fyTokenBal - fyTokenBalBefore;
        uint256 fyTokenChange = pool.getFYTokenBalance() - fyTokenBal;

        require(base.balanceOf(bob) == userBaseBefore + baseOut);

        almostEqual(fyTokenIn, expectedFYTokenIn, 1);

        (uint112 baseBalAfter, uint112 fyTokenBalAfter,) = pool.getCache();

        require(baseBalAfter == pool.getBaseBalance());
        require(fyTokenBalAfter + fyTokenChange == pool.getFYTokenBalance());
    }

    function testUnit_tradeUSDC05() public {
        console.log("does not buy base beyond slippage");
        uint128 baseOut = 1e6;
        fyToken.mint(address(pool), initialFYTokens);
        vm.expectRevert(bytes("Pool: Too much fyToken in"));
        pool.buyBase(bob, baseOut, 0);
    }

    function testUnit_tradeUSDC06() public {
        console.log("buys base and retrieves change");
        uint256 bobBaseBefore = base.balanceOf(bob);
        uint256 aliceFYTokenBefore = fyToken.balanceOf(alice);
        uint128 baseOut = uint128(1e6);

        fyToken.mint(address(pool), initialFYTokens);

        vm.prank(alice);
        pool.buyBase(bob, baseOut, uint128(MAX));
        require(base.balanceOf(bob) == bobBaseBefore + baseOut);

        (uint112 baseBal, uint112 fyTokenBal,) = pool.getCache();
        require(baseBal == pool.getBaseBalance());
        require(fyTokenBal != pool.getFYTokenBalance());

        vm.prank(alice);
        pool.retrieveFYToken(alice);

        require(fyToken.balanceOf(alice) > aliceFYTokenBefore);
    }

}

contract TradeUSDC__WithExtraFYToken is WithExtraFYTokenUSDC {
    using Math64x64 for uint256;
    using Math64x64 for int128;

    function testUnit_tradeUSDC07() public {
        uint128 baseIn = uint128(25000 * 1e6);
        uint256 userFYTokenBefore = fyToken.balanceOf(bob);
        uint256 userBaseBalanceBefore = base.balanceOf(alice);
        uint128 virtFYTokenBal = uint128(fyToken.balanceOf(address(pool)) + pool.totalSupply());
        uint128 sharesReserves = uint128(base.balanceOf(address(pool)));
        int128 c_ = (base.pricePerShare().fromUInt()).div(uint256(1e6).fromUInt());

        // Transfer base for sale to the pool
        base.mint(address(pool), baseIn);
        uint256 expectedFYTokenOut = YieldMath.fyTokenOutForSharesIn(
            sharesReserves * 1e12,
            virtFYTokenBal * 1e12,
            baseIn * 1e12,
            maturity - uint32(block.timestamp),
            k,
            g1,
            c_,
            mu
        ) / 1e12;

        vm.prank(alice);
        pool.sellBase(bob, 0);

        uint256 fyTokenOut = fyToken.balanceOf(bob) - userFYTokenBefore;
        require(base.balanceOf(alice) == userBaseBalanceBefore, "'From' wallet should have no base tokens");
        require(fyTokenOut == expectedFYTokenOut);
        (uint112 baseBal, uint112 fyTokenBal,) = pool.getCache();
        require(baseBal == pool.getBaseBalance());
        require(fyTokenBal == pool.getFYTokenBalance());
    }

    function testUnit_tradeUSDC08() public {
        console.log("does not sell base beyond slippage");
        uint128 baseIn = uint128(1e6);
        base.mint(address(pool), baseIn);

        vm.expectRevert(bytes("Pool: Not enough fyToken obtained"));
        vm.prank(alice);
        pool.sellBase(bob, uint128(MAX));
    }

    function testUnit_tradeUSDC09() public {
        console.log("donates fyToken and sells base");
        uint128 baseIn = uint128(1e6);
        uint128 fyTokenDonation = uint128(1e6);

        fyToken.mint(address(pool), fyTokenDonation);
        base.mint(address(pool), baseIn);

        vm.prank(alice);
        pool.sellBase(bob, 0);

        (uint112 baseBalAfter, uint112 fyTokenBalAfter,) = pool.getCache();

        require(baseBalAfter == pool.getBaseBalance());
        require(fyTokenBalAfter == pool.getFYTokenBalance());
    }

    function testUnit_tradeUSDC10() public {
        console.log("buys a certain amount of fyTokens with base");
        (uint112 baseCachedBefore,,) = pool.getCache();
        uint256 userFYTokenBefore = fyToken.balanceOf(bob);
        uint128 fyTokenOut = uint128(1e6);

        uint128 virtFYTokenBal = uint128(fyToken.balanceOf(address(pool)) + pool.totalSupply());
        uint128 sharesReserves = uint128(base.balanceOf(address(pool)));
        int128 c_ = (base.pricePerShare().fromUInt()).div(uint256(1e6).fromUInt());

        // Transfer base for sale to the pool
        base.mint(address(pool), initialBase);

        uint256 expectedBaseIn = YieldMath.sharesInForFYTokenOut(
            sharesReserves,
            virtFYTokenBal,
            fyTokenOut,
            maturity - uint32(block.timestamp),
            k,
            g1,
            c_,
            mu
        );

        vm.prank(alice);
        pool.buyFYToken(bob, fyTokenOut, uint128(MAX));

        (uint112 baseCachedCurrent, uint112 fyTokenCachedCurrent,) = pool.getCache();

        uint256 baseIn = baseCachedCurrent - baseCachedBefore;
        uint256 baseChange = pool.getBaseBalance() - baseCachedCurrent;

        require(
            fyToken.balanceOf(bob) == userFYTokenBefore + fyTokenOut,
            "'User2' wallet should have 1 fyToken token"
        );

        almostEqual(baseIn, expectedBaseIn, baseIn / 100000);
        require(baseCachedCurrent + baseChange == pool.getBaseBalance());
        require(fyTokenCachedCurrent == pool.getFYTokenBalance());
    }

    function testUnit_tradeUSDC11() public {
        console.log("does not buy fyToken beyond slippage");
        uint128 fyTokenOut = uint128(1e6);

        base.mint(address(pool), initialBase);
        vm.expectRevert(bytes("Pool: Too much base token in"));
        pool.buyFYToken(alice, fyTokenOut, 0);
    }

    function testUnit_tradeUSDC12() public {
        console.log("donates base and buys fyToken");
        uint256 baseBalances = pool.getBaseBalance();
        uint256 fyTokenBalances = pool.getFYTokenBalance();
        (uint112 baseCachedBefore,,) = pool.getCache();

        uint128 fyTokenOut = uint128(1e6);
        uint128 baseDonation = uint128(1e6);

        base.mint(address(pool), initialBase + baseDonation);

        pool.buyFYToken(bob, fyTokenOut, uint128(MAX));

        (uint112 baseCachedCurrent, uint112 fyTokenCachedCurrent,) = pool.getCache();
        uint256 baseIn = baseCachedCurrent - baseCachedBefore;

        require(baseCachedCurrent == baseBalances + baseIn);
        require(fyTokenCachedCurrent == fyTokenBalances - fyTokenOut);
    }
}
