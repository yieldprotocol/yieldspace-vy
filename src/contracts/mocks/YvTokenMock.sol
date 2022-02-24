// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.11;

import "@yield-protocol/utils-v2/contracts/token/ERC20.sol";

// TODO: This is a dropin replacement for @yield-protocol/vault-v2/contracts/mocks/YvTokenMock.sol
//       because I was having problems with that npm package

contract YvTokenMock is ERC20 {
    ERC20 public token;
    uint256 public price;

    constructor(string memory name, string memory symbol, uint8 decimals, ERC20 token_) ERC20(name, symbol, decimals) {
        token = token_;
    }

    /// @dev Give tokens to whoever asks for them.
    function mint(address to, uint256 amount) public virtual {
        _mint(to, amount);
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

    function set(uint256 price_) external {
        price = price_;
    }

    function pricePerShare() public view returns (uint256) {
        return price;
    }
}