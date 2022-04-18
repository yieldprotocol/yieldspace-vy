// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.13;

import "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {console} from "forge-std/console.sol";

import {Exp64x64} from "../../contracts/Exp64x64.sol";
import {Math64x64} from "../../contracts/Math64x64.sol";
import {YieldMath} from "../../contracts/YieldMath.sol";

import "./Utils.sol";
import "./Constants.sol";
import {TestCore} from "./TestCore.sol";
import {Pool} from "../../contracts/Pool/Pool.sol";
import {FYTokenMock} from "../mocks/FYTokenMock.sol";
import {YVTokenMock} from "../mocks/YVTokenMock.sol";

struct ZeroStateParams {
    string fyName;
    string fySymbol;
    string baseName;
    string baseSymbol;
    uint8 baseDecimals;
}

abstract contract ZeroState is TestCore {
    using Exp64x64 for uint128;
    using Math64x64 for int256;
    using Math64x64 for int128;
    using Math64x64 for uint128;
    using Math64x64 for uint256;

    string public baseName;
    string public baseSymbol;
    uint8 public baseDecimals;

    string public fyName;
    string public fySymbol;

    constructor(ZeroStateParams memory params) {
        fyName = params.fyName;
        fySymbol = params.fySymbol;
        baseName = params.baseName;
        baseSymbol = params.baseSymbol;
        baseDecimals = params.baseDecimals;
    }

    function setUp() public virtual {
        ts = ONE.div(uint256(25 * 365 * 24 * 60 * 60 * 10).fromUInt());
        // setup mock tokens
        base = new YVTokenMock(baseName, baseSymbol, baseDecimals, address(0));
        base.setPrice((muNumerator * (10**base.decimals())) / muDenominator);
        fyToken = new FYTokenMock(fyName, fySymbol, address(base), maturity);

        // setup pool
        pool = new Pool(address(base), address(fyToken), ts, g1Fee);

        // setup users
        alice = address(0xbabe);
        vm.label(alice, "alice");
        bob = address(0xb0b);
        vm.label(bob, "bob");
    }
}

abstract contract ZeroStateDai is ZeroState {
    // used in 2 test suites __WithLiquidity

    uint256 public constant aliceYVInitialBalance = 1000 * 1e18;
    uint256 public constant bobYVInitialBalance = 2_000_000 * 1e18;

    uint256 public constant initialBase = 1_100_000 * 1e18;
    uint256 public constant initialFYTokens = 1_500_000 * 1e18;

    ZeroStateParams public zeroStateParams =
        ZeroStateParams("fyYVDai1", "fyToken yvDAI maturity 1", "yvDAI", "Yearn Vault DAI", 18);

    constructor() ZeroState(zeroStateParams) {}

    function setUp() public virtual override {
        super.setUp();

        base.mint(alice, aliceYVInitialBalance);
        base.mint(bob, bobYVInitialBalance);
    }
}

abstract contract ZeroStateUSDC is ZeroState {
    // used in 2 test suites __WithLiquidity

    uint256 public constant aliceYVInitialBalance = 1000 * 1e6;
    uint256 public constant bobYVInitialBalance = 2_000_000 * 1e6;

    uint256 public constant initialFYTokens = 1_500_000 * 1e6;
    uint256 public constant initialBase = 1_100_000 * 1e6;

    ZeroStateParams public zeroStateParams =
        ZeroStateParams("fyYVUSDC1", "fyToken yvUSDC maturity 1", "yvUSDC", "Yearn Vault USDC", 6);

    constructor() ZeroState(zeroStateParams) {}

    function setUp() public virtual override {
        super.setUp();

        base.mint(alice, aliceYVInitialBalance);
        base.mint(bob, bobYVInitialBalance);
    }
}
