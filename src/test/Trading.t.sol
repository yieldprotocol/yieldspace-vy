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
        base.setPrice((cNumerator * 1e18) / cDenominator);
        fyToken = new FYTokenMock("fyToken yvDai maturity 1", FY_SYMBOL, address(base), maturity);
        fyToken.name();
        fyToken.symbol();

        // setup pool
        pool = new Pool(address(base), address(fyToken), ts, g1, g2, mu);

        base.mint(address(pool), initialBase);
        pool.mint(address(0), address(0), 0, MAX);
        fyToken.mint(address(pool), initialFYTokens);
        pool.sync();

        // assign tokenList params
        tokenList[0] = address(base);
        tokenList[1] = address(fyToken);

        // setup users
        alice = new ERC20User("alice", tokenList);
        bob = new ERC20User("bob", tokenList);
    }
}

contract Trade__ZeroState is ZeroState {
    using Math64x64 for uint256;
    using Math64x64 for int128;

    function testUnit_trade1() public {
        console.log("sells fyToken");
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

    function testUnit_trade2() public {
        console.log("does not sell fyToken beyond slippage");
        uint256 fyTokenIn = 1e18;
        fyToken.mint(address(pool), fyTokenIn);
        vm.expectRevert(bytes("Pool: Not enough base obtained"));
        pool.sellFYToken(address(bob), type(uint128).max);
    }

    function testUnit_trade3() public {
        console.log("donates base and sells fyToken");

        uint256 baseDonation = WAD;
        uint256 fyTokenIn = WAD;

        base.mint(address(pool), baseDonation);
        fyToken.mint(address(pool), fyTokenIn);

        vm.prank(address(bob));
        pool.sellFYToken(address(bob), 0);

        (uint112 baseBal, uint112 fyTokenBal, uint32 unused) = pool.getCache();
        require(baseBal == pool.getBaseBalance());
        require(fyTokenBal == pool.getFYTokenBalance());
    }
    function testUnit_trade4() public {
        console.log("buys base");
        (uint112 baseBalBefore, uint112 fyTokenBalBefore, uint32 unused) = pool.getCache();

        uint256 userBaseBefore = base.balanceOf(address(alice));
        uint128 baseOut = uint128(WAD);

    // const fyTokenInPreview = await pool.buyBasePreview(baseOut)
    // const expectedFYTokenIn = await poolEstimator.buyBase(baseOut)

        fyToken.mint(address(pool), initialFYTokens);

        vm.prank(address(bob));
        pool.buyBase(address(bob), uint128(baseOut), type(uint128).max);
    //   .to.emit(pool, 'Trade')
    //   .withArgs(maturity, user1, user2, baseOut, (await pool.getCache())[1].sub(fyTokenCachedBefore).mul(-1))

        (uint112 baseBal, uint112 fyTokenBal, uint32 unused1) = pool.getCache();


        uint256 fyTokenIn = fyTokenBal - fyTokenBalBefore;
        uint256 fyTokenChange = pool.getFYTokenBalance() - fyTokenBal;

        require(base.balanceOf(address(bob)) == userBaseBefore + baseOut);

        // almostEqual(fyTokenIn, expectedFYTokenIn, baseOut /1000000);
        // almostEqual(fyTokenInPreview, expectedFYTokenIn, baseOut.div(1000000))

        (uint112 baseBalAfter, uint112 fyTokenBalAfter, uint32 unused2) = pool.getCache();

        require(baseBalAfter == pool.getBaseBalance());
        require(fyTokenBalAfter + fyTokenChange == pool.getFYTokenBalance());
    }
}
