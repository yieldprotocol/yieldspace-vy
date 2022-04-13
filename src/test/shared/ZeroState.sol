// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.13;

import "forge-std/stdlib.sol";
import {Vm} from "forge-std/Vm.sol";
import {console} from "forge-std/console.sol";

import "./Utils.sol";
import "./Constants.sol";
import {Pool} from "../../contracts/Pool/Pool.sol";
import {TestCore} from "./TestCore.sol";
import {Exp64x64} from "../../contracts/Exp64x64.sol";
import {FYTokenMock} from "../mocks/FYTokenMock.sol";
import {YVTokenMock} from "../mocks/YVTokenMock.sol";
import {Math64x64} from "../../contracts/Math64x64.sol";
import {YieldMath} from "../../contracts/YieldMath.sol";

struct ZeroStateParams {
    string baseName;
    string baseSymbol;
    uint8 baseDecimals;
    string fyName;
    string fySymbol;
}

abstract contract ZeroState is TestCore {
    using Math64x64 for int128;
    using Math64x64 for uint128;
    using Math64x64 for int256;
    using Math64x64 for uint256;
    using Exp64x64 for uint128;

    string public baseName;
    string public baseSymbol;
    uint8 public baseDecimals;

    string public fyName;
    string public fySymbol;

    constructor(ZeroStateParams memory params) {
        baseName = params.baseName;
        baseSymbol = params.baseSymbol;
        baseDecimals = params.baseDecimals;
        fyName = params.fyName;
        fySymbol = params.fySymbol;
    }

    function setUp() public virtual {
        ts = ONE.div(uint256(25 * 365 * 24 * 60 * 60 * 10).fromUInt());
        // setup mock tokens
        base = new YVTokenMock(baseName, baseSymbol, baseDecimals, address(0));
        base.setPrice(cNumerator * 1e18 / cDenominator);
        fyToken = new FYTokenMock(fyName, fySymbol, address(base), maturity);

        // setup pool
        pool = new Pool(address(base), address(fyToken), ts, g1, g2, mu);

        // setup users
        alice = address(1);
        vm.label(address(alice), "alice");
        bob = address(2);
        vm.label(address(bob), "bob");

    }
}

abstract contract ZeroStateDai is ZeroState {
    // used in 2 test suites __WithLiquidity

    uint256 public constant aliceYVInitialBalance = 1000 * 1e18;
    uint256 public constant bobYVInitialBalance = 2_000_000 * 1e18;


    uint256 public constant initialFYTokens = 1_500_000 * 1e18;
    uint256 public constant initialBase = 1_100_000 * 1e18;

    function setUp() public virtual override {
        super.setUp();

        base.mint(alice, aliceYVInitialBalance);
        base.mint(bob, bobYVInitialBalance);

    }

    ZeroStateParams public zeroStateParams = ZeroStateParams(
        "yvDAI",
        "Yearn Vault DAI",
        18,
        "fyYVDai1",
        "fyToken yvDAI maturity 1"
    );

    constructor() ZeroState(zeroStateParams) {}

}
abstract contract ZeroStateUSDC is ZeroState {
    // used in 2 test suites __WithLiquidity

    uint256 public constant aliceYVInitialBalance = 1000 * 1e6;
    uint256 public constant bobYVInitialBalance = 2_000_000 * 1e6;


    uint256 public constant initialFYTokens = 1_500_000 * 1e6;
    uint256 public constant initialBase = 1_100_000 * 1e6;

    ZeroStateParams public zeroStateParams = ZeroStateParams(
        "yvUSDC",
        "Yearn Vault USDC",
        6,
        "fyYVUSDC1",
        "fyToken yvUSDC maturity 1"
    );

    constructor() ZeroState(zeroStateParams) {}

}
