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

contract Admin__WithLiquidity is WithLiquidity {
    function testUnit_admin1() public {
        console.log("external getters return correct info");
    }
    function testUnit_admin2() public {
        console.log("unauthorized users cannot change fees");
    }

    function testUnit_admin3() public {
        console.log("sync() updates cumulativeBalancesRatioLast");
    }

    function testUnit_admin4() public {
        console.log("getCumulativeRatioCurrent returns");
        uint104 x;
    }

}
