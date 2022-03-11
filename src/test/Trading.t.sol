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
abstract contract TradingTestCore is DSTest {
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
    // function withLiquiditySetup() public {
    //     base.mint(address(pool), INITIAL_BASE);

    //     vm.prank(user1);
    //     pool.mint(user1, user2, 0, MAX);

    //     uint256 additionalFYToken = INITIAL_BASE / 9;
    //     // Skew the balances without using trading functions
    //     fyToken.mint(address(pool), additionalFYToken);

    //     vm.prank(user1);
    //     pool.sync();
    // }

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

contract ZeroState__Trading is TradingTestCore {
    function setUp() external {
        zeroStateSetup();
        PoolUser(user1).setYVTokenBalance(user1YVInitialBalance);
        PoolUser(user2).setYVTokenBalance(user2YVInitialBalance);
    }

    function testUnit_trading1() public {
        console.log("sells fyToken");
    }

}

