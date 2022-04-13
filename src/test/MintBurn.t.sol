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

import "forge-std/stdlib.sol";
import {Vm} from "forge-std/Vm.sol";
import {console} from "forge-std/console.sol";

import "./shared/Utils.sol";
import "./shared/Constants.sol";
import {ZeroStateDai} from "./shared/ZeroState.sol";

import {Exp64x64} from "../contracts/Exp64x64.sol";
import {Math64x64} from "../contracts/Math64x64.sol";
import {YieldMath} from "../contracts/YieldMath.sol";


abstract contract WithLiquidity is ZeroStateDai {
    function setUp() public virtual override {
        super.setUp();
        base.mint(address(pool), INITIAL_BASE * 10**(base.decimals()));

        pool.mint(alice, bob, 0, MAX);
        base.setPrice((cNumerator * (10**base.decimals())) / cDenominator);
        uint256 additionalFYToken = (INITIAL_BASE * 10**(base.decimals())) / 9;

        // Skew the balances without using trading functions
        fyToken.mint(address(pool), additionalFYToken);

        pool.sync();
    }
}

contract Mint__ZeroState is ZeroStateDai {
    function testUnit_mint1() public {
        console.log("adds initial liquidity");

        vm.startPrank(bob);
        base.transfer(address(pool), INITIAL_YVDAI);

        vm.expectEmit(true, true, true, true);
        emit Liquidity(
            maturity,
            bob,
            bob,
            address(0),
            int256(-1 * int256(INITIAL_YVDAI)),
            int256(0),
            int256(INITIAL_YVDAI)
        );

        pool.mint(bob, bob, 0, MAX);
        base.setPrice((cNumerator * (10**base.decimals())) / cDenominator);

        require(pool.balanceOf(bob) == INITIAL_YVDAI);
        (uint112 baseBal, uint112 fyTokenBal,) = pool.getCache();
        require(baseBal == pool.getBaseBalance());
        require(fyTokenBal == pool.getFYTokenBalance());
    }

    function testUnit_mint2() public {
        console.log("adds liquidity with zero fyToken");
        base.mint(address(pool), INITIAL_YVDAI);

        vm.startPrank(alice);

        pool.mint(address(0), address(0), 0, MAX);

        // After initializing, donate base and sync to simulate having reached zero fyToken through trading
        base.mint(address(pool), INITIAL_YVDAI);
        pool.sync();

        base.mint(address(pool), INITIAL_YVDAI);
        pool.mint(bob, bob, 0, MAX);


        require(pool.balanceOf(bob) == INITIAL_YVDAI / 2);
        (uint112 baseBal, uint112 fyTokenBal,) = pool.getCache();
        require(baseBal == pool.getBaseBalance());
        require(fyTokenBal == pool.getFYTokenBalance());
    }

    function testUnit_mint3() public {
        console.log("syncs balances after donations");

        base.mint(address(pool), INITIAL_YVDAI);
        fyToken.mint(address(pool), INITIAL_YVDAI / 9);

        vm.expectEmit(false, false, false, true);
        emit Sync(uint112(INITIAL_YVDAI), uint112(INITIAL_YVDAI / 9), 0);

        vm.prank(alice);
        pool.sync();

        (uint112 baseBal, uint112 fyTokenBal,) = pool.getCache();
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

        uint256 poolTokensBefore = pool.balanceOf(bob);

        base.mint(address(pool), expectedBaseIn + 1e18); // send an extra wad of base
        fyToken.mint(address(pool), fyTokenIn);

        vm.startPrank(alice);
        pool.mint(bob, bob, 0, MAX);

        uint256 minted = pool.balanceOf(bob) - poolTokensBefore;

        almostEqual(minted, expectedMint, fyTokenIn / 10000);
        almostEqual(base.balanceOf(bob), WAD + bobYVInitialBalance, fyTokenIn / 10000);

        (uint112 baseBal, uint112 fyTokenBal,) = pool.getCache();

        require(baseBal == pool.getBaseBalance());
        require(fyTokenBal == pool.getFYTokenBalance());
    }

}

contract Burn__WithLiquidity is WithLiquidity {
    function testUnit_burn1() public {
        console.log("burns liquidity tokens");
        uint256 baseBalance = base.balanceOf(address(pool));
        uint256 fyTokenBalance = fyToken.balanceOf(address(pool));
        uint256 poolSup = pool.totalSupply();
        uint256 lpTokensIn = WAD;

        address charlie = address(3);

        uint256 expectedBaseOut = (lpTokensIn * baseBalance) / poolSup;
        uint256 expectedFYTokenOut = (lpTokensIn * fyTokenBalance) / poolSup;

        // alice transfers in lp tokens then burns them
        vm.prank(alice);
        pool.transfer(address(pool), lpTokensIn);

        vm.expectEmit(true, true, true, true);
        emit Liquidity(
            maturity,
            alice,
            bob,
            charlie,
            int256(expectedBaseOut),
            int256(expectedFYTokenOut),
            -int256(lpTokensIn)
        );
        vm.prank(alice);
        pool.burn(bob, address(charlie), 0, MAX);


        uint256 baseOut = baseBalance - base.balanceOf(address(pool));
        uint256 fyTokenOut = fyTokenBalance - fyToken.balanceOf(address(pool));
        almostEqual(baseOut, expectedBaseOut, baseOut / 10000);
        almostEqual(fyTokenOut, expectedFYTokenOut, fyTokenOut / 10000);

        (uint112 baseBal, uint112 fyTokenBal,) = pool.getCache();
        require(baseBal == pool.getBaseBalance());
        require(fyTokenBal == pool.getFYTokenBalance());
        require(base.balanceOf(bob) - bobYVInitialBalance == baseOut);
        require(fyToken.balanceOf(address(charlie)) == fyTokenOut);
    }
}
