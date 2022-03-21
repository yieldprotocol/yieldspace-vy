// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.12;

import {Mintable as ERC20} from "src/test/mocks/YVTokenMock.sol";
import "forge-std/stdlib.sol";
import {console} from "forge-std/console.sol";


/// @author @devtooligan -- adapted from Solmate.ERC20User
contract ERC20User {

    modifier validSymbol(string calldata symbol) {
        require(symbolToToken_[symbol] != address(0), "unknown token symbol");
        _;
    }

    Vm public constant vm = Vm(address(uint160(uint256(keccak256('hevm cheat code')))));
    mapping(string => address) private symbolToToken_; // token addys by symbol
    string public name;

    constructor(
        string memory name_,
        address[] memory erc20Tokens
    ) {
        name = name_;
        vm.label(address(this), name_);

        // register tokens
        // NOTE: When passing in the tokenList from another contract, you will need to do the following
        // to coerce the array because Solidity.  Assume you have 2 tokens:
        //     address[] memory tokenList = address[](2);  // !!!
        //     tokenList[0] = tokenAddr1;
        //     tokenList[1] = tokenAddr2;
        //     ERC20User alice = ERC20User("alice", tokenList);
        for (uint idx; idx < erc20Tokens.length; ++idx) {
            symbolToToken_[ERC20(erc20Tokens[idx]).symbol()] = erc20Tokens[idx];
        }
    }

    /// @notice This takes a "SYMBOL" and returns an ERC20 token that will be chained with a ERC20 function call.
    /// @dev While retrieving the token, vm.prank() is called so the very next call will be performed as if it's this
    /// user and now can be chained like:
    ///
    ///           alice.tokens("DAI").transfer(bob, 1e18)
    ///
    function tokens(string calldata symbol) public validSymbol(symbol) returns(ERC20) {
        vm.prank(address(this));  // <<- sneaky
        return ERC20(symbolToToken_[symbol]);
    }

    function setBalance(string calldata symbol, uint256 amount) public validSymbol(symbol) {
        ERC20 token = ERC20(symbolToToken_[symbol]);
        uint256 bal = token.balanceOf(address(this));
        if (bal == amount) return;
        if (bal < amount) {
            token.mint(address(this), amount - bal);
        } else {
            token.transfer(address(0), bal - amount);
        }
    }

}
