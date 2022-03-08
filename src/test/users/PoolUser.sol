// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.11;

import "@yield-protocol/vault-interfaces/IFYToken.sol";
import {IYVToken} from "src/contracts/interfaces/IYVToken.sol";

/// @author Adapted from Solmate.ERC20User
contract PoolUser {
    IYVToken public immutable yvToken;
    IFYToken public immutable fyToken;

    constructor(
        address yvToken_,
        address fyToken_
    ) {
        yvToken = IYVToken(yvToken_);
        fyToken = IFYToken(fyToken_);
    }
    function setYVTokenBalance(uint256 amount) public {
        yvToken.mint(address(this), amount);
    }

    function setFYTokenBalance(uint256 amount) public {
        fyToken.mint(address(this), amount);
    }

    function approveYVToken(address spender, uint256 amount) public virtual returns (bool) {
        return yvToken.approve(spender, amount);
    }

    function approveFYToken(address spender, uint256 amount) public virtual returns (bool) {
        return    fyToken.approve(spender, amount);
    }

    function transferYVToken(address to, uint256 amount) public virtual returns (bool) {
        return yvToken.transfer(to, amount);
    }

    function transferFYToken(address to, uint256 amount) public virtual returns (bool) {
        return fyToken.transfer(to, amount);
    }

    function transferYVTokenFrom(
        address from,
        address to,
        uint256 amount
    )  public virtual returns (bool) {
        return   yvToken.transferFrom(from, to, amount);
    }

    function transferFYTokenFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual returns (bool) {
        return fyToken.transferFrom(from, to, amount);
    }
}
