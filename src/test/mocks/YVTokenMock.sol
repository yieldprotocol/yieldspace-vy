// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.11;

import "@yield-protocol/utils-v2/contracts/token/ERC20.sol";
import {IERC20Metadata} from "@yield-protocol/utils-v2/contracts/token/IERC20Metadata.sol";

import {IYVToken} from "../../contracts/interfaces/IYVToken.sol";

// TODO: This is a dropin replacement for @yield-protocol/vault-v2/contracts/mocks/YVTokenMock.sol

abstract contract Mintable is ERC20 {
    /// @dev Give tokens to whoever asks for them.
    function mint(address to, uint256 amount) public virtual {
        _mint(to, amount);
    }
}
contract YVTokenMock is Mintable {
    IERC20Metadata public token;
    uint256 public price;

    constructor(string memory name, string memory symbol, uint8 decimals, address token_) ERC20(name, symbol, decimals) {
        token = IERC20Metadata(token_);
    }


    function deposit(uint256 deposited, address to) public returns (uint256 minted) {
        token.transferFrom(msg.sender, address(this), deposited);
        minted = deposited * token.decimals() / price;
        _mint(to, minted);
    }

    function withdraw(uint256 withdrawn, address to) public returns (uint256 obtained) {
        obtained = withdrawn * price / token.decimals();
        _burn(msg.sender, withdrawn);
        token.transfer(to, obtained);
    }

    function pricePerShare() public view virtual returns (uint256) {
        return price;
    }

    function setPrice(uint256 price_) public {
        price = price_;
    }
}