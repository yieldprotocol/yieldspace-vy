// // SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "@yield-protocol/yieldspace-interfaces/IPool.sol";
import "../YieldMath.sol";

library YieldMathExtensions {
    /// @dev Calculate the invariant for this pool
    // function invariant(IPool pool) external view returns (uint128) {
    //     uint32 maturity = pool.maturity();
    //     uint32 timeToMaturity = (maturity > uint32(block.timestamp))
    //         ? maturity - uint32(block.timestamp)
    //         : 0;
    //     return
    //         YieldMath.invariant(
    //             pool.getBaseBalance(),
    //             pool.getFYTokenBalance(),
    //             pool.totalSupply(),
    //             timeToMaturity,
    //             pool.ts()
    //         );
    // }

    // // @dev max amount of fyTokens that can be bought from the pool
    // function maxFYTokenOut(IPool pool) external view returns (uint128) {
    //     (uint112 _baseCached, uint112 _fyTokenCached, ) = pool.getCache();
    //     uint96 scaleFactor = pool.scaleFactor();
    //     return
    //         YieldMath.maxFYTokenOut(
    //             _baseCached * scaleFactor,
    //             _fyTokenCached * scaleFactor,
    //             pool.maturity() - uint32(block.timestamp),
    //             pool.ts(),
    //             pool.g1(),
    //             int128(107 * 10**16),
    //             int128(107 * 10**16)
    //         ) / scaleFactor;
    // }

    // /// @dev max amount of fyTokens that can be sold into the pool
    // function maxFYTokenIn(IPool pool) external view returns (uint128) {
    //     (, uint112 _baseCached, uint112 _fyTokenCached, ) = pool.getCache();
    //     uint96 scaleFactor = pool.scaleFactor();
    //     return
    //         YieldMath.maxFYTokenIn(
    //             _baseCached * scaleFactor,
    //             _fyTokenCached * scaleFactor,
    //             pool.maturity() - uint32(block.timestamp),
    //             pool.ts(),
    //             pool.g2(),
    //             int128(107 * 10**16),
    //             int128(107 * 10**16)
    //         ) / scaleFactor;
    // }

    /// @dev max amount of Base that can be sold to the pool
    // function maxBaseIn(IPool pool) external view returns (uint128) {
    //     (uint112 _baseCached, uint112 _fyTokenCached, ) = pool.getCache();
    //     uint96 scaleFactor = pool.scaleFactor();
    //     return
    //         YieldMath.maxBaseIn(
    //             _baseCached * scaleFactor,
    //             _fyTokenCached * scaleFactor,
    //             pool.maturity() - uint32(block.timestamp),
    //             pool.ts(), // TODO: Is there a better way than calling all these fns?
    //             pool.g1(),
    //             1, // pool.base.pricePerShare()
    //             2 // pool.mu()
    //         ) / scaleFactor;
    // }

    /// @dev max amount of Base that can be bought from the pool
    // function maxBaseOut(IPool pool) external view returns (uint128) {
    //     (uint112 _baseCached, uint112 _fyTokenCached, ) = pool.getCache();
    //     uint96 scaleFactor = pool.scaleFactor();
    //     return
    //         YieldMath.maxBaseOut(
    //             _baseCached * scaleFactor,
    //             _fyTokenCached * scaleFactor,
    //             pool.maturity() - uint32(block.timestamp),
    //             pool.ts(),
    //             pool.g2()
    //         ) / scaleFactor;
    // }
}
