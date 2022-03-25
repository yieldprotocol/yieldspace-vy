// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.13;

import "@yield-protocol/utils-v2/contracts/token/IERC20Metadata.sol";
import "forge-std/stdlib.sol";
import {console} from "forge-std/console.sol";
import {IYVPool} from "../../contracts/interfaces/IYVPool.sol";
import {ERC20User} from "./ERC20User.sol";

/// @author @devtooligan -- inherits ERC20User -- allows for:
///                   alice.pool.sellFYToken(...)
///
contract PoolUser is ERC20User {

    address private pool_; // pool addys for lookup by index

    constructor(
        string memory name_,
        address[] memory erc20Tokens,
        address poolAddress
    ) ERC20User(name_, erc20Tokens) {
        pool_ = poolAddress;

    }

    /// @notice This returns an IVYPool token that will be chained with a IVYPool function call.
    /// @dev While retrieving the token, vm.prank() is called so the very next call will be performed as if it's this
    /// user and now can be chained like:
    ///
    ///           alice.pool(pool.symbol()).mint(...)
    ///
    /// One limitation to this is that the call to alice.pool() is considered an external call so you can't do
    /// expectEmit right before this.  For expectEmit, don't use alice.pool(), instead use prank and call pool directly:
    /// vm.expectEmit(false, false, false, false);
    /// emit MyEvent();
    /// vm.prank(address(alice)); <<==
    /// pool.whatever(); <<==
    function pool() public returns(IYVPool) {
        vm.prank(address(this));  // <<- sneaky
        return IYVPool(pool_);
    }
}
