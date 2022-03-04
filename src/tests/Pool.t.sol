// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.11;

import "ds-test/test.sol";

import {Pool} from "src/contracts/Pool.sol";


contract PoolTest is DSTest {

    Pool pool; // TODO: make this a ManiputablePool
    YvTokenSub yvToken;
    FyTokenSub fyToken;

    function setUp() external {
        pool = new Pool

        MockFactory factoryMock = new MockFactory();
        factoryMock.setGlobals(address(globals));

        loan = new ManipulatableMapleLoan();

        loan.__setFactory(address(factoryMock));
    }

}