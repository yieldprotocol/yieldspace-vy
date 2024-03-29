// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;
import "@yield-protocol/utils-v2/contracts/token/IERC20Metadata.sol";
import "@yield-protocol/utils-v2/contracts/token/ERC20.sol";
import "@yield-protocol/utils-v2/contracts/token/IERC20.sol";

// TODO: import this from vault-v2 repo?
interface IYVToken is IERC20, IERC20Metadata {
    // @notice Returns the price for a single Yearn Vault share.
    // @dev total vault assets / total token supply (calculated not cached)
    function pricePerShare() external view returns (uint256);

    function mint(address, uint256) external;


}
