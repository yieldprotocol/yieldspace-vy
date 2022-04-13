// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.13;

import "forge-std/stdlib.sol";
import {Vm} from "forge-std/Vm.sol";
import {console} from "forge-std/console.sol";

import "./shared/Utils.sol";
import "./shared/Constants.sol";
import {Pool} from "../contracts/Pool/Pool.sol";
import {ZeroStateDai} from "./shared/ZeroState.sol";
import {Exp64x64} from "../contracts/Exp64x64.sol";
import {FYTokenMock} from "./mocks/FYTokenMock.sol";
import {YVTokenMock} from "./mocks/YVTokenMock.sol";
import {Math64x64} from "../contracts/Math64x64.sol";
import {YieldMath} from "../contracts/YieldMath.sol";


abstract contract WithExtraFYToken is ZeroStateDai {
    using Math64x64 for int128;
    using Math64x64 for uint128;
    using Math64x64 for int256;
    using Math64x64 for uint256;
    using Exp64x64 for uint128;

    function setUp() public virtual override {
        super.setUp();
        uint256 additionalFYToken = 30 * WAD;
        fyToken.mint(address(this), additionalFYToken);
        vm.prank(address(alice));
        pool.sellFYToken(address(this), 0);
    }
}

abstract contract OnceMature is WithExtraFYToken {
    using Math64x64 for int128;
    using Math64x64 for uint128;
    using Math64x64 for int256;
    using Math64x64 for uint256;
    using Exp64x64 for uint128;

    function setUp() public override {
        super.setUp();
        vm.warp(pool.maturity());
    }
}

contract TradeDAI__ZeroState is ZeroStateDai {
    using Math64x64 for uint256;
    using Math64x64 for int128;

    function testUnit_tradeDAI01() public {
        console.log("sells a certain amount of fyToken for base");
        uint256 fyTokenIn = 25_000 * 1e18;
        uint256 bobBaseBefore = base.balanceOf(address(bob));

        uint128 virtFYTokenBal = uint128(fyToken.balanceOf(address(pool)) + pool.totalSupply());
        uint128 sharesReserves = uint128(base.balanceOf(address(pool)));
        int128 c_ = (base.pricePerShare().fromUInt()).div(uint256(1e18).fromUInt());

        fyToken.mint(address(pool), fyTokenIn);
        uint256 expectedBaseOut = YieldMath.sharesOutForFYTokenIn(
            sharesReserves,
            virtFYTokenBal,
            uint128(fyTokenIn),
            maturity - uint32(block.timestamp),
            k,
            g2,
            c_,
            mu
        );
        vm.expectEmit(true, true, false, true);
        emit Trade(maturity, address(alice), address(bob), int256(expectedBaseOut), -int256(fyTokenIn));
        vm.prank(address(alice));
        pool.sellFYToken(address(bob), 0);
        uint256 bobBaseAfter = base.balanceOf(address(bob));

        uint256 baseOut = base.balanceOf(address(bob)) - bobBaseBefore;
        (uint112 baseBal, uint112 fyTokenBal, uint32 unused) = pool.getCache();
        require(baseBal == pool.getBaseBalance());
        require(fyTokenBal == pool.getFYTokenBalance());
    }

    function testUnit_tradeDAI02() public {
        console.log("does not sell fyToken beyond slippage");
        uint256 fyTokenIn = 1e18;
        fyToken.mint(address(pool), fyTokenIn);
        vm.expectRevert(bytes("Pool: Not enough base obtained"));
        pool.sellFYToken(address(bob), type(uint128).max);
    }

    function testUnit_tradeDAI03() public {
        console.log("donates base and sells fyToken");

        uint256 baseDonation = WAD;
        uint256 fyTokenIn = WAD;

        base.mint(address(pool), baseDonation);
        fyToken.mint(address(pool), fyTokenIn);

        vm.prank(bob);
        pool.sellFYToken(address(bob), 0);

        (uint112 baseBal, uint112 fyTokenBal, uint32 unused) = pool.getCache();
        require(baseBal == pool.getBaseBalance());
        require(fyTokenBal == pool.getFYTokenBalance());
    }

    function testUnit_tradeDAI04() public {
        console.log("buys a certain amount base for fyToken");
        (uint112 baseBalBefore, uint112 fyTokenBalBefore, uint32 unused) = pool.getCache();

        uint256 userBaseBefore = base.balanceOf(address(alice));
        uint128 baseOut = uint128(WAD);

        uint128 virtFYTokenBal = uint128(fyToken.balanceOf(address(pool)) + pool.totalSupply());
        uint128 sharesReserves = uint128(base.balanceOf(address(pool)));
        int128 c_ = (base.pricePerShare().fromUInt()).div(uint256(1e18).fromUInt());

        fyToken.mint(address(pool), initialFYTokens); // send some tokens to the pool

        uint256 expectedFYTokenIn = YieldMath.fyTokenInForSharesOut(
            sharesReserves,
            virtFYTokenBal,
            baseOut,
            maturity - uint32(block.timestamp),
            k,
            g2,
            c_,
            mu
        );

        vm.expectEmit(true, true, false, true);
        emit Trade(maturity, address(bob), address(bob), int256(int128(baseOut)), -int256(expectedFYTokenIn));
        vm.prank(address(bob));
        pool.buyBase(address(bob), uint128(baseOut), type(uint128).max);

        (uint112 baseBal, uint112 fyTokenBal, uint32 unused1) = pool.getCache();
        uint256 fyTokenIn = fyTokenBal - fyTokenBalBefore;
        uint256 fyTokenChange = pool.getFYTokenBalance() - fyTokenBal;

        require(base.balanceOf(address(bob)) == userBaseBefore + baseOut);

        almostEqual(fyTokenIn, expectedFYTokenIn, baseOut / 1000000);

        (uint112 baseBalAfter, uint112 fyTokenBalAfter, uint32 unused2) = pool.getCache();

        require(baseBalAfter == pool.getBaseBalance());
        require(fyTokenBalAfter + fyTokenChange == pool.getFYTokenBalance());
    }

    function testUnit_tradeDAI05() public {
        console.log("does not buy base beyond slippage");
        uint128 baseOut = 1e18;
        fyToken.mint(address(pool), initialFYTokens);
        vm.expectRevert(bytes("Pool: Too much fyToken in"));
        pool.buyBase(address(bob), baseOut, 0);
    }

    function testUnit_tradeDAI06() public {
        console.log("buys base and retrieves change");
        uint256 userBaseBefore = base.balanceOf(address(alice));
        uint256 userFYTokenBefore = fyToken.balanceOf(address(alice));
        uint128 baseOut = uint128(WAD);

        fyToken.mint(address(pool), initialFYTokens);

        vm.startPrank(alice);
        pool.buyBase(address(bob), baseOut, uint128(MAX));
        require(base.balanceOf(address(bob)) == userBaseBefore + baseOut);

        (uint112 baseBal, uint112 fyTokenBal, uint32 unused) = pool.getCache();
        require(baseBal == pool.getBaseBalance());
        require(fyTokenBal != pool.getFYTokenBalance());

        pool.retrieveFYToken(address(alice));

        require(fyToken.balanceOf(address(alice)) > userFYTokenBefore);
    }
}

contract TradeDAI__WithExtraFYToken is WithExtraFYToken {
    using Math64x64 for uint256;
    using Math64x64 for int128;

    function testUnit_tradeDAI07() public {
        console.log("sells base for a certain amount of FYTokens");
        uint128 baseIn = uint128(WAD);
        uint256 userFYTokenBefore = fyToken.balanceOf(address(bob));

        uint128 virtFYTokenBal = uint128(fyToken.balanceOf(address(pool)) + pool.totalSupply());
        uint128 sharesReserves = uint128(base.balanceOf(address(pool)));
        int128 c_ = (base.pricePerShare().fromUInt()).div(uint256(1e18).fromUInt());

        // Transfer base for sale to the pool
        base.mint(address(pool), baseIn);

        uint256 expectedFYTokenOut = YieldMath.fyTokenOutForSharesIn(
            sharesReserves,
            virtFYTokenBal,
            baseIn,
            maturity - uint32(block.timestamp),
            k,
            g1,
            c_,
            mu
        );

        vm.expectEmit(true, true, false, true);
        emit Trade(maturity, address(alice), address(bob), -int128(baseIn), int256(expectedFYTokenOut));

        vm.prank(address(alice));
        pool.sellBase(address(bob), 0);

        uint256 fyTokenOut = fyToken.balanceOf(address(bob)) - userFYTokenBefore;
        require(base.balanceOf(address(alice)) == 0, "'From' wallet should have no base tokens");
        require(fyTokenOut == expectedFYTokenOut);
        (uint112 baseBal, uint112 fyTokenBal, uint32 unused) = pool.getCache();
        require(baseBal == pool.getBaseBalance());
        require(fyTokenBal == pool.getFYTokenBalance());
    }

    function testUnit_tradeDAI08() public {
        console.log("does not sell base beyond slippage");
        uint128 baseIn = uint128(WAD);
        base.mint(address(pool), baseIn);

        vm.expectRevert(bytes("Pool: Not enough fyToken obtained"));
        vm.prank(address(alice));
        pool.sellBase(address(bob), uint128(MAX));
    }

    function testUnit_tradeDAI09() public {
        console.log("donates fyToken and sells base");
        uint128 baseIn = uint128(WAD);
        uint128 fyTokenDonation = uint128(WAD);

        fyToken.mint(address(pool), fyTokenDonation);
        base.mint(address(pool), baseIn);

        vm.prank(alice);
        pool.sellBase(address(bob), 0);

        (uint112 baseBalAfter, uint112 fyTokenBalAfter, uint32 unused2) = pool.getCache();

        require(baseBalAfter == pool.getBaseBalance());
        require(fyTokenBalAfter == pool.getFYTokenBalance());
    }

    function testUnit_tradeDAI10() public {
        console.log("buys a certain amount of fyTokens with base");
        (uint112 baseCachedBefore, uint112 unused1, uint32 unused2) = pool.getCache();
        uint256 userFYTokenBefore = fyToken.balanceOf(address(bob));
        uint128 fyTokenOut = uint128(WAD);

        uint128 virtFYTokenBal = uint128(fyToken.balanceOf(address(pool)) + pool.totalSupply());
        uint128 sharesReserves = uint128(base.balanceOf(address(pool)));
        int128 c_ = (base.pricePerShare().fromUInt()).div(uint256(1e18).fromUInt());

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

        vm.expectEmit(true, true, false, true);
        emit Trade(maturity, address(alice), address(bob), -int128(int256(expectedBaseIn)), int256(int128(fyTokenOut)));

        vm.prank(address(alice));
        pool.buyFYToken(address(bob), fyTokenOut, uint128(MAX));

        (uint112 baseCachedCurrent, uint112 fyTokenCachedCurrent, uint32 unused4) = pool.getCache();

        uint256 baseIn = baseCachedCurrent - baseCachedBefore;
        uint256 baseChange = pool.getBaseBalance() - baseCachedCurrent;

        require(
            fyToken.balanceOf(address(bob)) == userFYTokenBefore + fyTokenOut,
            "'User2' wallet should have 1 fyToken token"
        );

        almostEqual(baseIn, expectedBaseIn, baseIn / 1000000);
        require(baseCachedCurrent + baseChange == pool.getBaseBalance());
        require(fyTokenCachedCurrent == pool.getFYTokenBalance());
    }

    function testUnit_tradeDAI11() public {
        console.log("does not buy fyToken beyond slippage");
        uint128 fyTokenOut = uint128(WAD);

        base.mint(address(pool), initialBase);
        vm.expectRevert(bytes("Pool: Too much base token in"));
        pool.buyFYToken(address(alice), fyTokenOut, 0);
    }

    function testUnit_tradeDAI12() public {
        console.log("donates base and buys fyToken");
        uint256 baseBalances = pool.getBaseBalance();
        uint256 fyTokenBalances = pool.getFYTokenBalance();
        (uint112 baseCachedBefore, uint112 unused1, uint32 unused2) = pool.getCache();

        uint128 fyTokenOut = uint128(WAD);
        uint128 baseDonation = uint128(WAD);

        base.mint(address(pool), initialBase + baseDonation);

        pool.buyFYToken(address(bob), fyTokenOut, uint128(MAX));

        (uint112 baseCachedCurrent, uint112 fyTokenCachedCurrent, uint32 unused4) = pool.getCache();
        uint256 baseIn = baseCachedCurrent - baseCachedBefore;

        require(baseCachedCurrent == baseBalances + baseIn);
        require(fyTokenCachedCurrent == fyTokenBalances - fyTokenOut);
    }
}

contract TradeDAI__OnceMature is OnceMature {
    using Math64x64 for uint256;
    using Math64x64 for int128;

    function testUnit_tradeDAI13() internal {
        console.log("doesn't allow sellBase");
        vm.expectRevert(bytes("Pool: Too late"));
        pool.sellBasePreview(uint128(WAD));
        vm.expectRevert(bytes("Pool: Too late"));
        pool.sellBase(address(alice), 0);
    }

    function testUnit_tradeDAI14() internal {
        console.log("doesn't allow buyBase");
        vm.expectRevert(bytes("Pool: Too late"));
        pool.buyBasePreview(uint128(WAD));
        vm.expectRevert(bytes("Pool: Too late"));
        pool.buyBase(address(alice), uint128(WAD), uint128(MAX));
    }

    function testUnit_tradeDAI15() internal {
        console.log("doesn't allow sellFYToken");
        vm.expectRevert(bytes("Pool: Too late"));
        pool.sellFYTokenPreview(uint128(WAD));
        vm.expectRevert(bytes("Pool: Too late"));
        pool.sellFYToken(address(alice), 0);
    }

    function testUnit_tradeDAI16() internal {
        console.log("doesn't allow buyFYToken");
        vm.expectRevert(bytes("Pool: Too late"));
        pool.buyFYTokenPreview(uint128(WAD));
        vm.expectRevert(bytes("Pool: Too late"));
        pool.buyFYToken(address(alice), uint128(WAD), uint128(MAX));
    }
}
