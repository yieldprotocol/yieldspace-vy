// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.12;

import "forge-std/stdlib.sol";
import {Vm} from "forge-std/Vm.sol";
import {console} from "forge-std/console.sol";

import "./Utils.sol";
import "./Constants.sol";
import {Pool} from "../../contracts/Pool.sol";
import {TestCore} from "./TestCore.sol";
import {PoolUser} from "../users/PoolUser.sol";
import {Exp64x64} from "../../contracts/Exp64x64.sol";
import {FYTokenMock} from "../mocks/FYTokenMock.sol";
import {YVTokenMock} from "../mocks/YVTokenMock.sol";
import {Math64x64} from "../../contracts/Math64x64.sol";
import {YieldMath} from "../../contracts/YieldMath.sol";

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

    // setup tokenlist for params to PoolUser because passing arrays in Solidity is weird
    address[] public tokenList = new address[](2); // !!!

    function setUp() public virtual {
        ts = ONE.div(uint256(25 * 365 * 24 * 60 * 60 * 10).fromUInt());
        // setup mock tokens
        base = new YVTokenMock("Yearn Vault Dai", BASE, 18, address(0));
        base.setPrice(cNumerator * 1e18 / cDenominator);
        fyToken = new FYTokenMock("fyToken yvDai maturity 1", FYTOKEN, address(base), maturity);
        fyToken.name();
        fyToken.symbol();

        // setup pool
        pool = new Pool(address(base), address(fyToken), ts, g1, g2, mu);

        // assign tokenList params
        tokenList[0] = address(base);
        tokenList[1] = address(fyToken);

        // setup users
        alice = new PoolUser("alice", tokenList, address(pool));
        alice.setBalance(base.symbol(), aliceYVInitialBalance);
        bob = new PoolUser("bob", tokenList, address(pool));
        bob.setBalance(base.symbol(), bobYVInitialBalance);
    }
}
