// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;
import "@yield-protocol/utils-v2/contracts/token/IERC20.sol";
import "@yield-protocol/utils-v2/contracts/token/IERC2612.sol";
import "@yield-protocol/vault-interfaces/IFYToken.sol";
import "src/contracts/interfaces/IYVToken.sol";

// There are some new things in the pool that we need to include in this interface so not sure if
// we can keep using this or how to proceed.  Changes:
// base() returns IYVToken
// function mu() external view returns(int128);
// function getBaseCurrentPrice() external view returns (uint256);
// Also questioning the name -- IYVPool? Will this replace normal Pool? or will
// we have both running at same time.  Anyways IYVPool has "yearn vault" a little too
// baked in.  We also use terms like "shares", "variable yield", and "yield bearing vaults"
// hmmm after just writing those out, I kinda like "yield bearing" yb.
// Also FYToken or FyToken -- debate
interface IYVPool is IERC20, IERC2612 {
    function getBaseCurrentPrice() external view returns (uint256); // new
    function mu() external view returns(int128); // new
    function base() external view returns(IYVToken); // updated
    function ts() external view returns(int128);
    function g1() external view returns(int128);
    function g2() external view returns(int128);
    function maturity() external view returns(uint32);
    function scaleFactor() external view returns(uint96);
    function getCache() external view returns (uint112, uint112, uint32);
    function fyToken() external view returns(IFYToken);
    function getBaseBalance() external view returns(uint112);
    function getFYTokenBalance() external view returns(uint112);
    function retrieveBase(address to) external returns(uint128 retrieved);
    function retrieveFYToken(address to) external returns(uint128 retrieved);
    function sellBase(address to, uint128 min) external returns(uint128);
    function buyBase(address to, uint128 baseOut, uint128 max) external returns(uint128);
    function sellFYToken(address to, uint128 min) external returns(uint128);
    function buyFYToken(address to, uint128 fyTokenOut, uint128 max) external returns(uint128);
    function sellBasePreview(uint128 baseIn) external returns(uint128);
    // function sellBasePreview(uint128 baseIn) external view returns(uint128);
    function buyBasePreview(uint128 baseOut) external returns(uint128);
    // function buyBasePreview(uint128 baseOut) external view returns(uint128);
    function sellFYTokenPreview(uint128 fyTokenIn) external returns(uint128);
    // function sellFYTokenPreview(uint128 fyTokenIn) external view returns(uint128);
    function buyFYTokenPreview(uint128 fyTokenOut) external returns(uint128);
    // function buyFYTokenPreview(uint128 fyTokenOut) external view returns(uint128);
    function mint(address to, address remainder, uint256 minRatio, uint256 maxRatio) external returns (uint256, uint256, uint256);
    function mintWithBase(address to, address remainder, uint256 fyTokenToBuy, uint256 minRatio, uint256 maxRatio) external returns (uint256, uint256, uint256);
    function burn(address baseTo, address fyTokenTo, uint256 minRatio, uint256 maxRatio) external returns (uint256, uint256, uint256);
    function burnForBase(address to, uint256 minRatio, uint256 maxRatio) external returns (uint256, uint256);
}