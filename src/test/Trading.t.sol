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

// TODO: Create PoolUser then new wrapper User that is based on both

abstract contract ZeroState is TestCore {
    using Math64x64 for int128;
    using Math64x64 for uint128;
    using Math64x64 for int256;
    using Math64x64 for uint256;
    using Exp64x64 for uint128;

    uint256 public constant initialFYTokens = 1_500_000 * 1e18;
    uint256 public constant initialBase = 1_100_000 * 1e18;
    // uint256 public constant initialFYTokens = 1_500_000 * 1e18;
    // uint256 public constant initialBase = 1_100_000 * 1e18;

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

        console.log('fytokenbal0');
        console.log(fyToken.balanceOf(address(pool)));

        base.mint(address(pool), initialBase);
        pool.mint(address(0), address(0), 0, MAX);
        fyToken.mint(address(pool), initialFYTokens);
        console.log('fytokenbal1');
        console.log(fyToken.balanceOf(address(pool)));
        pool.sync();

        // assign tokenList params
        tokenList[0] = address(base);
        tokenList[1] = address(fyToken);

        // setup users
        alice = new ERC20User("alice", tokenList);
        // alice.setBalance(base.symbol(), 0); // Start w zero
        bob = new ERC20User("bob", tokenList);
        // bob.setBalance(base.symbol(), 0); // Start w zero
        console.log('fytokenbal3');
        console.log(fyToken.balanceOf(address(pool)));

    }
}

contract Trade__ZeroState is ZeroState {
    function testUnit_trade1() public {
        console.log("sells fyToken");
        uint256 fyTokenIn = 25_000 * 1e18;
        uint256 bobBaseBefore = base.balanceOf(address(bob));
        console.log('fytokenbal4');
        console.log(fyToken.balanceOf(address(pool)));

        console.log("Trading.t.sol ~ line 67 ~ testUnit_trade1 ~ bobBaseBefore");
        console.log(bobBaseBefore);
        fyToken.mint(address(pool), fyTokenIn);

        // vm.expectEmit(true, true, false, true);
        // emit Trade(maturity, address(alice), address(bob), int(bobBaseBefore), -int(fyTokenIn));
        vm.prank(address(alice));
        pool.sellFYToken(address(bob), 0);
        uint256 bobBaseAfter = base.balanceOf(address(bob));
        console.log("file: Trading.t.sol ~ line 76 ~ testUnit_trade1 ~ bobBaseAfter");
        console.log(bobBaseAfter);

        uint256 baseOut = base.balanceOf(address(bob)) - bobBaseBefore;
        console.log('base out', baseOut);
        (uint112 baseBal, uint112 fyTokenBal, uint32 unused) = pool.getCache();
        require(baseBal == pool.getBaseBalance());
        require(fyTokenBal == pool.getFYTokenBalance());
    }

}