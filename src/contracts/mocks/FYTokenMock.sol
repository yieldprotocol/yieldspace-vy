// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.11;

import "./YvTokenMock.sol";
import "@yield-protocol/utils-v2/contracts/token/ERC20Permit.sol";

contract FYTokenMock is ERC20Permit {
    YvTokenMock public yearnVault;
    uint32 public maturity;

    constructor (YvTokenMock yearnVault_, uint32 maturity_)
        ERC20Permit(
            "Test",
            "TST",
            IERC20Metadata(address(yearnVault_)).decimals()
    ) {
        yearnVault = yearnVault_;
        maturity = maturity_;
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) public {
        _burn(from, amount);
    }

    function redeem(address from, address to, uint256 amount) public {
        _burn(from, amount);
        yearnVault.mint(to, amount);
    }
}
