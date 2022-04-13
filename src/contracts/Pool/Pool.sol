// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;
import "./PoolImports.sol";

/*
  __     ___      _     _
  \ \   / (_)    | |   | |  ██████╗  ██████╗  ██████╗ ██╗        ███████╗ ██████╗ ██╗
   \ \_/ / _  ___| | __| |  ██╔══██╗██╔═══██╗██╔═══██╗██║        ██╔════╝██╔═══██╗██║
    \   / | |/ _ \ |/ _` |  ██████╔╝██║   ██║██║   ██║██║        ███████╗██║   ██║██║
     | |  | |  __/ | (_| |  ██╔═══╝ ██║   ██║██║   ██║██║        ╚════██║██║   ██║██║
     |_|  |_|\___|_|\__,_|  ██║     ╚██████╔╝╚██████╔╝███████╗██╗███████║╚██████╔╝███████╗
       yieldprotocol.com    ╚═╝      ╚═════╝  ╚═════╝ ╚══════╝╚═╝╚══════╝ ╚═════╝ ╚══════╝

                                                ┌─────────┐
                                                │no       │
                                                │lifeguard│
                                                └─┬─────┬─┘       ==+
                             I'm Poolie!          │     │    =======+
                                             _____│_____│______    |+
                                      \  .-'"___________________`-.|+
                                        ( .'"                   '-.)+
                                        |`-..__________________..-'|+
                                        |                          |+
             .-:::::::::::-.            |                          |+      ┌──────────────┐
           .:::::::::::::::::.          |         ---  ---         |+      │$            $│
          :  _______  __   __ :        .|         (o)  (o)         |+.     │ ┌────────────┴─┐
         :: |       ||  | |  |::      /`|                          |+'\    │ │$            $│
        ::: |    ___||  |_|  |:::    / /|            [             |+\ \   │$│ ┌────────────┴─┐
        ::: |   |___ |       |:::   / / |        ----------        |+ \ \  └─┤ │$            $│
        ::: |    ___||_     _|:::.-" ;  \        \________/        /+  \ "--/│$│    SHARES    │
        ::: |   |      |   |  ::),.-'    `-..__________________..-' +=  `---=└─┤              │
         :: |___|      |___|  ::=/              |    | |    |                  │$            $│
          :       TOKEN       :                 |    | |    |                  └──────────────┘
           `:::::::::::::::::'                  |    | |    |
             `-:::::::::::-'                    +----+ +----+
                `'''''''`                  _..._|____| |____| _..._
                                         .` "-. `%   | |    %` .-" `.
                                        /      \    .: :.     /      \
                                        '-..___|_..=:` `-:=.._|___..-'
*/

/// A Yieldspace AMM implementation for pools providing liquidity for fyTokens and tokenized vault tokens.
/// https://hackmd.io/lRZ4mgdrRgOpxZQXqKYlFw
/// @title  Pool.sol
/// @dev Instantiate pool with Yearn token and associated fyToken.
/// Uses 64.64 bit math under the hood for precision and reduced gas usage.
/// @author Orignal work by @alcueca. Adapted by @devtooligan
contract Pool is PoolEvents, IYVPool, ERC20Permit {

    /* LIBRARIES
     *****************************************************************************************************************/

    using CastU256U128 for uint256;
    using CastU256U112 for uint256;
    using CastU256I256 for uint256;
    using CastU128U112 for uint128;
    using CastU128I128 for uint128;
    using Math64x64 for uint256;
    using Math64x64 for int128;
    using MinimalTransferHelper for IFYToken;
    using MinimalTransferHelper for IYVToken;

    /* MODIFIERS
     *****************************************************************************************************************/

    /// Trading can only be done before maturity
    modifier beforeMaturity() {
        if (block.timestamp >= maturity) {
            revert AfterMaturity();
        }
        _;
    }

    /* IMMUTABLES
     *****************************************************************************************************************/

    int128 public immutable mu; //                     The normalization coefficient -- which is the initial c value
    int128 public immutable override ts; //            1 / seconds in 10 years, in 64.64
    int128 public immutable override g1; //            To be used when selling base to the pool
    int128 public immutable override g2; //            To be used when selling fyToken to the pool
    uint64 public immutable override maturity;
    uint64 public immutable override scaleFactor; //   Scale up to 18 decimal tokens to get the right precision

    IYVToken public immutable override base;
    IFYToken public immutable override fyToken;

    /* STORAGE
     *****************************************************************************************************************/

    uint112 private baseCached; //                     uses single storage slot, accessible via getCache
    uint112 private fyTokenCached; //                  uses single storage slot, accessible via getCache
    uint32 private blockTimestampLast; //              uses single storage slot, accessible via getCache
    uint256 public cumulativeBalancesRatio; //         Fixed point factor with 27 decimals (ray)

    /* CONSTRUCTOR
     *****************************************************************************************************************/
    constructor(
        address base_,
        address fyToken_,
        int128 ts_,
        int128 g1_,
        int128 g2_,
        int128 mu_
    )
        ERC20Permit(
            string(abi.encodePacked(IERC20Metadata(fyToken_).name(), " LP")),
            string(abi.encodePacked(IERC20Metadata(fyToken_).symbol(), "LP")),
            IERC20Metadata(fyToken_).decimals()
        )
    {
        fyToken = IFYToken(fyToken_);
        base = IYVToken(base_);

        if ((maturity = uint32(IFYToken(fyToken_).maturity())) > type(uint32).max) {
            revert MaturityOverflow();
        }

        ts = ts_;
        g1 = g1_;
        g2 = g2_;

        scaleFactor = uint64(10**(18 - uint96(decimals)));
        mu = mu_;
    }

    /* BALANCE MANAGEMENT FUNCTIONS
     *****************************************************************************************************************//*
                  _____________________________________
                   |o o o o o o o o o o o o o o o o o|
                   |o o o o o o o o o o o o o o o o o|
                   ||_|_|_|_|_|_|_|_|_|_|_|_|_|_|_|_||
                   || | | | | | | | | | | | | | | | ||
                   |o o o o o o o o o o o o o o o o o|
                   |o o o o o o o o o o o o o o o o o|
                   |o o o o o o o o o o o o o o o o o|
                   |o o o o o o o o o o o o o o o o o|
                  _|o_o_o_o_o_o_o_o_o_o_o_o_o_o_o_o_o|_
                          "Poolie's Abacus" - ejm */

    /// Returns the cached balances & last updated timestamp.
    /// @return Cached base token balance.
    /// @return Cached virtual FY token balance.
    /// @return Timestamp that balances were last cached.
    function getCache()
        external
        view
        override
        returns (
            uint112,
            uint112,
            uint32
        )
    {
        return (baseCached, fyTokenCached, blockTimestampLast);
    }

    /// Updates the cache to match the actual balances.
    function sync() external {
        _update(_getBaseBalance(), _getFYTokenBalance(), baseCached, fyTokenCached);
    }

    /// Returns the "virtual" fyToken balance, which is the real balance plus the pool token supply.
    function getFYTokenBalance() public view override returns (uint112) {
        return _getFYTokenBalance();
    }

    /// Returns the base balance
    function getBaseBalance() public view override returns (uint112) {
        return _getBaseBalance();
    }

    /// Returns the base current price
    function getBaseCurrentPrice() public view returns (uint256) {
        return base.pricePerShare();
    }

    /// Returns the "virtual" fyToken balance, which is the real balance plus the pool token supply.
    function _getFYTokenBalance() internal view returns (uint112) {
        return (fyToken.balanceOf(address(this)) + _totalSupply).u112();
    }

    /// Returns the base balance
    function _getBaseBalance() internal view returns (uint112) {
        return base.balanceOf(address(this)).u112();
    }

    /// Returns the base current price
    function _getC() internal view returns (int128) {
        return ((base.pricePerShare() * scaleFactor).fromUInt()).div(uint256(1e18).fromUInt());
    }

    /// Retrieve any base tokens not accounted for in the cache
    function retrieveBase(address to) external override returns (uint128 retrieved) {
        retrieved = _getBaseBalance() - baseCached; // Cache can never be above balances
        base.safeTransfer(to, retrieved);
        // Now the current balances match the cache, so no need to update the TWAR
    }

    /// Retrieve any fyTokens not accounted for in the cache
    function retrieveFYToken(address to) external override returns (uint128 retrieved) {
        retrieved = _getFYTokenBalance() - fyTokenCached; // Cache can never be above balances
        fyToken.safeTransfer(to, retrieved);
        // Now the balances match the cache, so no need to update the TWAR
    }

    /// Update cache and, on the first call per block, ratio accumulators
    function _update(
        uint128 baseBalance,
        uint128 fyBalance,
        uint112 baseCached_,
        uint112 fyTokenCached_
    ) private {
        uint32 blockTimestamp = uint32(block.timestamp);
        uint32 timeElapsed;
        unchecked {
            timeElapsed = blockTimestamp - blockTimestampLast; // underflow is desired
        }
        uint256 cumulativeBalancesRatio_ = cumulativeBalancesRatio;
        if (timeElapsed > 0 && baseCached_ != 0 && fyTokenCached_ != 0) {
            // We multiply by 1e27 here so that r = t * y/x is a fixed point factor with 27 decimals
            uint256 scaledFYTokenCached = uint256(fyTokenCached_) * 1e27;
            cumulativeBalancesRatio_ += (scaledFYTokenCached * timeElapsed) / baseCached_;
            cumulativeBalancesRatio = cumulativeBalancesRatio_;
        }
        baseCached = baseBalance.u112();
        fyTokenCached = fyBalance.u112();
        blockTimestampLast = blockTimestamp;
        emit Sync(baseCached, fyTokenCached, cumulativeBalancesRatio_);
    }

    /* LIQUIDITY FUNCTIONS

        ┌───────────────────────────────────────────┐
        │  mint new life. gm!                       │
        │  buy, sell, mint more, buy, sell -- stop  │
        │  mature. burn. gg.                        │
        │                                           │
        │  "Watashinojinsei" - a haiku by Poolie    │
        └───────────────────────────────────────────┘

     *****************************************************************************************************************/

    /*mint
                                                                                              v
         ___                                                                            \            /
         |_ \_/                   ┌───────────────────────────────┐
         |   |                    │                               │                 `    _......._     '   GM!
                                 \│                               │/                  .-:::::::::::-.
           │                     \│                               │/             `   :    __    ____ :   /
           └───────────────►      │            mint               │                 ::   / /   / __ \::
                                  │                               │  ──────▶    _   ::  / /   / /_/ /::   _
           ┌───────────────►      │                               │                 :: / /___/ ____/ ::
           │                     /│                               │\                ::/_____/_/      ::
                                 /│                               │\             '   :               :   `
         B A S E                  │                      \(^o^)/  │                   `-:::::::::::-'
                                  │                     Pool.sol  │                 ,    `'''''''`     .
                                  └───────────────────────────────┘
                                                                                       /            \
                                                                                              ^
    */
    /// Mint liquidity tokens in exchange for adding base and fyToken
    /// The amount of liquidity tokens to mint is calculated from the amount of unaccounted for fyToken in this contract.
    /// A proportional amount of base tokens need to be present in this contract, also unaccounted for.
    /// @param to Wallet receiving the minted liquidity tokens.
    /// @param remainder Wallet receiving any surplus base.
    /// @param minRatio Minimum ratio of base to fyToken in the pool.
    /// @param maxRatio Maximum ratio of base to fyToken in the pool.
    /// @return The amount of liquidity tokens minted.
    function mint(
        address to,
        address remainder,
        uint256 minRatio,
        uint256 maxRatio
    )
        external
        override
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        return _mintInternal(to, remainder, 0, minRatio, maxRatio);
    }

    /*mintWithBase
                                                                                             V
                                  ┌───────────────────────────────┐                   \            /
                                  │                               │                 `    _......._     '   GM!
                                 \│                               │/                  .-:::::::::::-.
                                 \│                               │/             `   :    __    ____ :   /
                                  │         mintWithBase          │                 ::   / /   / __ \::
         B A S E     ──────►      │                               │  ──────▶    _   ::  / /   / /_/ /::   _
                                  │                               │                 :: / /___/ ____/ ::
                                 /│                               │\                ::/_____/_/      ::
                                 /│                               │\             '   :               :   `
                                  │                      \(^o^)/  │                   `-:::::::::::-'
                                  │                     Pool.sol  │                 ,    `'''''''`     .
                                  └───────────────────────────────┘                    /           \
                                                                                            ^
    */
    /// Mint liquidity tokens in exchange for adding only base
    /// The amount of liquidity tokens is calculated from the amount of fyToken to buy from the pool,
    /// plus the amount of unaccounted for fyToken in this contract.
    /// The base tokens need to be present in this contract, unaccounted for.
    /// @param to Wallet receiving the minted liquidity tokens.
    /// @param remainder Wallet receiving any surplus base.
    /// @param fyTokenToBuy Amount of `fyToken` being bought in the Pool, from this we calculate how much base it will be taken in.
    /// @param minRatio Minimum ratio of base to fyToken in the pool.
    /// @param maxRatio Maximum ratio of base to fyToken in the pool.
    /// @return The amount of liquidity tokens minted.
    function mintWithBase(
        address to,
        address remainder,
        uint256 fyTokenToBuy,
        uint256 minRatio,
        uint256 maxRatio
    )
        external
        override
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        return _mintInternal(to, remainder, fyTokenToBuy, minRatio, maxRatio);
    }

    /// Mint liquidity tokens, with an optional internal trade to buy fyToken beforehand.
    /// The amount of liquidity tokens is calculated from the amount of fyToken to buy from the pool,
    /// plus the amount of unaccounted for fyToken in this contract.
    /// The base tokens need to be present in this contract, unaccounted for.
    /// @param to Wallet receiving the minted liquidity tokens.
    /// @param remainder Wallet receiving any surplus base.
    /// @param fyTokenToBuy Amount of `fyToken` being bought in the Pool, from this we calculate how much base it will be taken in.
    /// @param minRatio Minimum ratio of base to fyToken in the pool.
    /// @param maxRatio Maximum ratio of base to fyToken in the pool.
    function _mintInternal(
        address to,
        address remainder,
        uint256 fyTokenToBuy,
        uint256 minRatio,
        uint256 maxRatio
    )
        internal
        returns (
            uint256 baseIn,
            uint256 fyTokenIn,
            uint256 tokensMinted
        )
    {
        // Gather data
        uint256 supply = _totalSupply;
        (uint112 baseCached_, uint112 fyTokenCached_) = (baseCached, fyTokenCached);
        uint256 realFYTokenCached_ = fyTokenCached_ - supply; // The fyToken cache includes the virtual fyToken, equal to the supply
        uint256 baseBalance = base.balanceOf(address(this));
        uint256 fyTokenBalance = fyToken.balanceOf(address(this));
        uint256 baseAvailable = baseBalance - baseCached_;

        // Check the burn wasn't sandwiched
        if (realFYTokenCached_ != 0) {
            if (
                ((uint256(baseCached_) * 1e18) / realFYTokenCached_ < minRatio &&
                    (uint256(baseCached_) * 1e18) / realFYTokenCached_ > maxRatio)
            ) {
                revert Slippage();
            }
        }

        // Calculate token amounts
        if (supply == 0) {
            // Initialize at 1 pool token minted per base token supplied
            baseIn = baseAvailable;
            tokensMinted = baseIn;
            //todo: set mu here
        } else if (realFYTokenCached_ == 0) {
            // Edge case, no fyToken in the Pool after initialization
            baseIn = baseAvailable;
            tokensMinted = (supply * baseIn) / baseCached_;
        } else {
            // There is an optional virtual trade before the mint
            uint256 baseToSell;
            if (fyTokenToBuy != 0) {
                baseToSell = _buyFYTokenPreview(fyTokenToBuy.u128(), baseCached_, fyTokenCached_);
            }

            // We use all the available fyTokens, plus a virtual trade if it happened, surplus is in base tokens
            fyTokenIn = fyTokenBalance - realFYTokenCached_;
            tokensMinted = (supply * (fyTokenToBuy + fyTokenIn)) / (realFYTokenCached_ - fyTokenToBuy);
            baseIn = baseToSell + ((baseCached_ + baseToSell) * tokensMinted) / supply;
            require(baseAvailable >= baseIn, "Pool: Not enough base token in");
        }

        // Update TWAR
        _update(
            (baseCached_ + baseIn).u128(),
            (fyTokenCached_ + fyTokenIn + tokensMinted).u128(), // Account for the "virtual" fyToken from the new minted LP tokens
            baseCached_,
            fyTokenCached_
        );

        // Execute mint
        _mint(to, tokensMinted);

        // Return any unused base
        if (baseAvailable - baseIn != 0) base.safeTransfer(remainder, baseAvailable - baseIn);

        emit Liquidity(
            maturity,
            msg.sender,
            to,
            address(0),
            -(baseIn.i256()),
            -(fyTokenIn.i256()),
            tokensMinted.i256()
        );
    }

    /* burn
                                (   (
                                )    (
                           (  (|   (|  )
                        )   )\/ ( \/(( (                  ___
                        ((  /     ))\))))\      ┌──────►  |_ \_/
                         )\(          |  )      │         |   |
                        /:  | __    ____/:      │
                        ::   / /   / __ \::  ───┤
                        ::  / /   / /_/ /::     │
                        :: / /___/ ____/ ::     └──────►  B A S E
                        ::/_____/_/      ::
                         :               :
                          `-:::::::::::-'
                             `'''''''`
    */
    /// Burn liquidity tokens in exchange for base and fyToken.
    /// The liquidity tokens need to be in this contract.
    /// @param baseTo Wallet receiving the base.
    /// @param fyTokenTo Wallet receiving the fyToken.
    /// @param minRatio Minimum ratio of base to fyToken in the pool.
    /// @param maxRatio Maximum ratio of base to fyToken in the pool.
    /// @return The amount of tokens burned and returned (tokensBurned, bases, fyTokens).
    function burn(
        address baseTo,
        address fyTokenTo,
        uint256 minRatio,
        uint256 maxRatio
    )
        external
        override
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        return _burnInternal(baseTo, fyTokenTo, false, minRatio, maxRatio);
    }

    /* burnForBase

                                (   (
                                )    (
                            (  (|   (|  )
                         )   )\/ ( \/(( (
                         ((  /     ))\))))\
                          )\(          |  )
                        /:  | __    ____/:
                        ::   / /   / __ \::    ──────────►   B A S E
                        ::  / /   / /_/ /::
                        :: / /___/ ____/ ::
                        ::/_____/_/      ::
                         :               :
                          `-:::::::::::-'
                             `'''''''`
    */
    /// Burn liquidity tokens in exchange for base.
    /// The liquidity provider needs to have called `pool.approve`.
    /// @param to Wallet receiving the base and fyToken.
    /// @param minRatio Minimum ratio of base to fyToken in the pool.
    /// @param maxRatio Minimum ratio of base to fyToken in the pool.
    /// @return tokensBurned The amount of lp tokens burned.
    /// @return baseOut The amount of base tokens returned.
    function burnForBase(
        address to,
        uint256 minRatio,
        uint256 maxRatio
    ) external override returns (uint256 tokensBurned, uint256 baseOut) {
        (tokensBurned, baseOut, ) = _burnInternal(to, address(0), true, minRatio, maxRatio);
    }

    /// Burn liquidity tokens in exchange for base.
    /// The liquidity provider needs to have called `pool.approve`.
    /// @param baseTo Wallet receiving the base.
    /// @param fyTokenTo Wallet receiving the fyToken.
    /// @param tradeToBase Whether the resulting fyToken should be traded for base tokens.
    /// @param minRatio Minimum ratio of base to fyToken in the pool.
    /// @param maxRatio Minimum ratio of base to fyToken in the pool.
    /// @return tokensBurned The amount of pool tokens burned.
    /// @return tokenOut The amount of base tokens returned.
    /// @return fyTokenOut The amount of fyTokens returned.
    function _burnInternal(
        address baseTo,
        address fyTokenTo,
        bool tradeToBase,
        uint256 minRatio,
        uint256 maxRatio
    )
        internal
        returns (
            uint256 tokensBurned,
            uint256 tokenOut,
            uint256 fyTokenOut
        )
    {
        // Gather data
        tokensBurned = _balanceOf[address(this)];
        uint256 supply = _totalSupply;
        (uint112 baseCached_, uint112 fyTokenCached_) = (baseCached, fyTokenCached);
        uint256 realFYTokenCached_ = fyTokenCached_ - supply; // The fyToken cache includes the virtual fyToken, equal to the supply

        // Check the burn wasn't sandwiched
        require(
            realFYTokenCached_ == 0 ||
                ((uint256(baseCached_) * 1e18) / realFYTokenCached_ >= minRatio &&
                    (uint256(baseCached_) * 1e18) / realFYTokenCached_ <= maxRatio),
            "Pool: Reserves ratio changed"
        );

        // Calculate trade
        tokenOut = (tokensBurned * baseCached_) / supply;
        fyTokenOut = (tokensBurned * realFYTokenCached_) / supply;

        if (tradeToBase) {
            tokenOut +=
                YieldMath.sharesOutForFYTokenIn( //                         This is a virtual sell
                    (baseCached_ - tokenOut.u128()) * scaleFactor, //      Cache, minus virtual burn
                    (fyTokenCached_ - fyTokenOut.u128()) * scaleFactor, // Cache, minus virtual burn
                    fyTokenOut.u128() * scaleFactor, //                    Sell the virtual fyToken obtained
                    maturity - uint32(block.timestamp), //                  This can't be called after maturity
                    ts,
                    g2,
                    _getC(),
                    mu
                ) /
                scaleFactor;
            fyTokenOut = 0;
        }

        // Update TWAR
        _update(
            (baseCached_ - tokenOut).u128(),
            (fyTokenCached_ - fyTokenOut - tokensBurned).u128(),
            baseCached_,
            fyTokenCached_
        );

        // Transfer assets
        _burn(address(this), tokensBurned);
        base.safeTransfer(baseTo, tokenOut);
        if (fyTokenOut != 0) fyToken.safeTransfer(fyTokenTo, fyTokenOut);

        emit Liquidity(
            maturity,
            msg.sender,
            baseTo,
            fyTokenTo,
            tokenOut.i256(),
            fyTokenOut.i256(),
            -(tokensBurned.i256())
        );
    }

    /* TRADING FUNCTIONS
     ****************************************************************************************************************/

    /* sellBase

                         I've transfered you `uint128 baseIn` worth of base.
             _______     Can you swap them for fyTokens?
            /   GUY \                                                 ┌─────────┐
     (^^^|   \===========  ┌──────────────┐                           │no       │
      \(\/    | _  _ |     │$            $│                           │lifeguard│
       \ \   (. o  o |     │ ┌────────────┴─┐                         └─┬─────┬─┘       ==+
        \ \   |   ~  |     │ │$            $│    hmm, let's see here    │     │    =======+
        \  \   \ == /      │ │              │                      _____│_____│______    |+
         \  \___|  |___    │$│   `baseIn`   │                  .-'"___________________`-.|+
          \ /   \__/   \   └─┤$            $│                 ( .'"                   '-.)+
           \            \    └──────────────┘                 |`-..__________________..-'|+
            --|  GUY |\_/\  / /                               |                          |+
              |      | \  \/ /                                |                          |+
              |      |  \   /         _......._             /`|       ---     ---        |+
              |      |   \_/       .-:::::::::::-.         / /|       (o )    (o )       |+
              |______|           .:::::::::::::::::.      / / |                          |+
              |__X___|          :  _______  __   __ : _.-" ;  |            [             |+
              |      |         :: |       ||  | |  |::),.-'   |        ----------        |+
              |  |   |        ::: |    ___||  |_|  |:::/      \        \________/        /+
              |  |  _|        ::: |   |___ |       |:::        `-..__________________..-' +=
              |  |  |         ::: |    ___||_     _|:::               |    | |    |
              |  |  |         ::: |   |      |   |  :::               |    | |    |
              (  (  |          :: |___|      |___|  ::                |    | |    |
              |  |  |           :      ????         :                 T----T T----T
              |  |  |            `:::::::::::::::::'             _..._L____J L____J _..._
             _|  |  |              `-:::::::::::-'             .` "-. `%   | |    %` .-" `.
            (_____[__)                `'''''''`               /      \    .: :.     /      \
                                                              '-..___|_..=:` `-:=.._|___..-'
 */
    /// Sell base for fyToken.
    /// The trader needs to have transferred the amount of base to sell to the pool before in the same transaction.
    /// @param to Wallet receiving the fyToken being bought
    /// @param min Minimm accepted amount of fyToken
    /// @return Amount of fyToken that will be deposited on `to` wallet
    function sellBase(address to, uint128 min) external override returns (uint128) {
        // Calculate trade
        (uint112 baseCached_, uint112 fyTokenCached_) = (baseCached, fyTokenCached);
        uint112 _baseBalance = _getBaseBalance();
        uint112 _fyTokenBalance = _getFYTokenBalance();
        uint128 baseIn = _baseBalance - baseCached_;
        uint128 fyTokenOut = _sellBasePreview(baseIn, baseCached_, _fyTokenBalance);

        // Slippage check
        require(fyTokenOut >= min, "Pool: Not enough fyToken obtained");

        // Update TWAR
        _update(_baseBalance, _fyTokenBalance - fyTokenOut, baseCached_, fyTokenCached_);

        // Transfer assets
        fyToken.safeTransfer(to, fyTokenOut);

        emit Trade(maturity, msg.sender, to, -(baseIn.i128()), fyTokenOut.i128());
        return fyTokenOut;
    }

    /// Returns how much fyToken would be obtained by selling `baseIn` base
    /// @param baseIn Amount of base hypothetically sold.
    /// @return Amount of fyToken hypothetically bought.
    function sellBasePreview(uint128 baseIn) external view override returns (uint128) {
        (uint112 baseCached_, uint112 fyTokenCached_) = (baseCached, fyTokenCached);
        return _sellBasePreview(baseIn, baseCached_, fyTokenCached_);
    }

    /// Returns how much fyToken would be obtained by selling `baseIn` base
    function _sellBasePreview(
        uint128 baseIn,
        uint112 baseBalance,
        uint112 fyTokenBalance
    ) private view beforeMaturity returns (uint128) {
        uint128 fyTokenOut = YieldMath.fyTokenOutForSharesIn(
            baseBalance * scaleFactor,
            fyTokenBalance * scaleFactor,
            baseIn * scaleFactor,
            maturity - uint32(block.timestamp), // This can't be called after maturity
            ts,
            g1,
            _getC(),
            mu
        ) / scaleFactor;

        require(fyTokenBalance - fyTokenOut >= baseBalance + baseIn, "Pool: fyToken balance too low");

        return fyTokenOut;
    }

    /* buyBase

                         I want `uint128 tokenOut` worth of base tokens.
             _______     I've approved fyTokens for you to take what you need for the swap.
            /   GUY \         .:::::::::::::::::.
     (^^^|   \===========    :  _______  __   __ :                 ┌─────────┐
      \(\/    | _  _ |      :: |       ||  | |  |::                │no       │
       \ \   (. o  o |     ::: |    ___||  |_|  |:::               │lifeguard│
        \ \   |   ~  |     ::: |   |___ |       |:::               └─┬─────┬─┘       ==+
        \  \   \ == /      ::: |    ___||_     _|:::    lfg!         │     │    =======+
         \  \___|  |___    ::: |   |      |   |  :::            _____│_____│______    |+
          \ /   \__/   \    :: |___|      |___|  ::         .-'"___________________`-.|+
           \            \    :        ????       :         ( .'"                   '-.)+
            --|  GUY |\_/\  / `:::::::::::::::::'          |`-..__________________..-'|+
              |      | \  \/ /  `-:::::::::::-'            |                          |+
              |      |  \   /      `'''''''`               |                          |+
              |      |   \_/                               |       ---     ---        |+
              |______|                                     |       (o )    (o )       |+
              |__X___|             ┌──────────────┐      /`|                          |+
              |      |             │$            $│     / /|            [             |+
              |  |   |             │   B A S E    │    / / |        ----------        |+
              |  |  _|             │  `tokenOut`  │\.-" ;  \        \________/        /+
              |  |  |              │$            $│),.-'    `-..__________________..-' +=
              |  |  |              └──────────────┘                |    | |    |
              (  (  |                                              |    | |    |
              |  |  |                                              |    | |    |
              |  |  |                                              T----T T----T
             _|  |  |                                         _..._L____J L____J _..._
            (_____[__)                                      .` "-. `%   | |    %` .-" `.
                                                           /      \    .: :.     /      \
                                                           '-..___|_..=:` `-:=.._|___..-'
 */
    /// Buy base for fyToken
    /// The trader needs to have called `fyToken.approve`
    /// @param to Wallet receiving the base being bought
    /// @param tokenOut Amount of base being bought that will be deposited in `to` wallet
    /// @param max Maximum amount of fyToken that will be paid for the trade
    /// @return Amount of fyToken that will be taken from caller
    function buyBase(
        address to,
        uint128 tokenOut,
        uint128 max
    ) external override returns (uint128) {
        // Calculate trade
        uint128 fyTokenBalance = _getFYTokenBalance();
        (uint112 baseCached_, uint112 fyTokenCached_) = (baseCached, fyTokenCached);
        uint128 fyTokenIn = _buyBasePreview(tokenOut, baseCached_, fyTokenCached_);
        require(fyTokenBalance - fyTokenCached_ >= fyTokenIn, "Pool: Not enough fyToken in");

        // Slippage check
        require(fyTokenIn <= max, "Pool: Too much fyToken in");

        // Update TWAR
        _update(baseCached_ - tokenOut, fyTokenCached_ + fyTokenIn, baseCached_, fyTokenCached_);

        // Transfer assets
        base.safeTransfer(to, tokenOut);

        emit Trade(maturity, msg.sender, to, tokenOut.i128(), -(fyTokenIn.i128()));
        return fyTokenIn;
    }

    /// Returns how much fyToken would be required to buy `tokenOut` base.
    /// @param tokenOut Amount of base hypothetically desired.
    /// @return Amount of fyToken hypothetically required.
    function buyBasePreview(uint128 tokenOut) external view override returns (uint128) {
        (uint112 baseCached_, uint112 fyTokenCached_) = (baseCached, fyTokenCached);
        return _buyBasePreview(tokenOut, baseCached_, fyTokenCached_);
    }

    /// Returns how much fyToken would be required to buy `tokenOut` base.
    function _buyBasePreview(
        uint128 tokenOut,
        uint112 baseBalance,
        uint112 fyTokenBalance
    ) private view beforeMaturity returns (uint128) {
        return
            YieldMath.fyTokenInForSharesOut(
                baseBalance * scaleFactor,
                fyTokenBalance * scaleFactor,
                tokenOut * scaleFactor,
                maturity - uint32(block.timestamp), // This can't be called after maturity
                ts,
                g2,
                _getC(),
                mu
            ) / scaleFactor;
    }

    /*sellFYToken
                         I've transferred you `uint128 fyTokenIn` worth of fyTokens.
             _______     Can you swap them for base?
            /   GUY \         .:::::::::::::::::.
     (^^^|   \===========    :  _______  __   __ :                 ┌─────────┐
      \(\/    | _  _ |      :: |       ||  | |  |::                │no       │
       \ \   (. o  o |     ::: |    ___||  |_|  |:::               │lifeguard│
        \ \   |   ~  |     ::: |   |___ |       |:::               └─┬─────┬─┘       ==+
        \  \   \ == /      ::: |    ___||_     _|:::   I think so.   │     │    =======+
         \  \___|  |___    ::: |   |      |   |  :::            _____│_____│______    |+
          \ /   \__/   \    :: |___|      |___|  ::         .-'"___________________`-.|+
           \            \    :     `fyTokenIn`   :         ( .'"                   '-.)+
            --|  GUY |\_/\  / `:::::::::::::::::'          |`-..__________________..-'|+
              |      | \  \/ /  `-:::::::::::-'            |                          |+
              |      |  \   /      `'''''''`               |                          |+
              |      |   \_/                               |       ---     ---        |+
              |______|                                     |       (o )    (o )       |+
              |__X___|             ┌──────────────┐      /`|                          |+
              |      |             │$            $│     / /|            [             |+
              |  |   |             │   B A S E    │    / / |        ----------        |+
              |  |  _|             │    ????      │\.-" ;  \        \________/        /+
              |  |  |              │$            $│),.-'    `-..__________________..-' +=
              |  |  |              └──────────────┘                |    | |    |
              (  (  |                                              |    | |    |
              |  |  |                                              |    | |    |
              |  |  |                                              T----T T----T
             _|  |  |                                         _..._L____J L____J _..._
            (_____[__)                                      .` "-. `%   | |    %` .-" `.
                                                           /      \    .: :.     /      \
                                                           '-..___|_..=:` `-:=.._|___..-'
 */
    /// Sell fyToken for base
    /// The trader needs to have transferred the amount of fyToken to sell to the pool before in the same transaction.
    /// @param to Wallet receiving the base being bought
    /// @param min Minimum accepted amount of base
    /// @return Amount of base that will be deposited on `to` wallet
    function sellFYToken(address to, uint128 min) external override returns (uint128) {
        // Calculate trade
        (uint112 baseCached_, uint112 fyTokenCached_) = (baseCached, fyTokenCached);
        uint112 _fyTokenBalance = _getFYTokenBalance();
        uint112 _baseBalance = _getBaseBalance();
        uint128 fyTokenIn = _fyTokenBalance - fyTokenCached_;
        uint128 baseOut = _sellFYTokenPreview(fyTokenIn, baseCached_, fyTokenCached_);

        // Slippage check
        require(baseOut >= min, "Pool: Not enough base obtained");

        // Update TWAR
        _update(_baseBalance - baseOut, _fyTokenBalance, baseCached_, fyTokenCached_);

        // Transfer assets
        base.safeTransfer(to, baseOut);

        emit Trade(maturity, msg.sender, to, baseOut.i128(), -(fyTokenIn.i128()));
        return baseOut;
    }

    /// Returns how much base would be obtained by selling `fyTokenIn` fyToken.
    /// @param fyTokenIn Amount of fyToken hypothetically sold.
    /// @return Amount of base hypothetically bought.
    function sellFYTokenPreview(uint128 fyTokenIn) public view returns (uint128) {
        (uint112 baseCached_, uint112 fyTokenCached_) = (baseCached, fyTokenCached);
        return _sellFYTokenPreview(fyTokenIn, baseCached_, fyTokenCached_);
    }

    /// Returns how much base would be obtained by selling `fyTokenIn` fyToken.
    function _sellFYTokenPreview(
        uint128 fyTokenIn,
        uint112 baseBalance,
        uint112 fyTokenBalance
    ) private view beforeMaturity returns (uint128) {
        return
            YieldMath.sharesOutForFYTokenIn(
                baseBalance * scaleFactor,
                fyTokenBalance * scaleFactor,
                fyTokenIn * scaleFactor,
                maturity - uint32(block.timestamp), // This can't be called after maturity
                ts,
                g2,
                _getC(),
                mu
            ) / scaleFactor;
    }

    /*buyFYToken

                         I want `uint128 fyTokenOut` worth of fyTokens.
             _______     I've approved base for you to take what you need for the swap.
            /   GUY \                                                 ┌─────────┐
     (^^^|   \===========  ┌──────────────┐                           │no       │
      \(\/    | _  _ |     │$            $│                           │lifeguard│
       \ \   (. o  o |     │ ┌────────────┴─┐                         └─┬─────┬─┘       ==+
        \ \   |   ~  |     │ │$            $│           Ok, Guy!        │     │    =======+
        \  \   \ == /      │ │   B A S E    │                      _____│_____│______    |+
         \  \___|  |___    │$│    ????      │                  .-'"___________________`-.|+
          \ /   \__/   \   └─┤$            $│                 ( .'"                   '-.)+
           \            \    └──────────────┘                 |`-..__________________..-'|+
            --|  GUY |\_/\  / /                               |                          |+
              |      | \  \/ /                                |                          |+
              |      |  \   /         _......._             /`|       ---     ---        |+
              |      |   \_/       .-:::::::::::-.         / /|       (o )    (o )       |+
              |______|           .:::::::::::::::::.      / / |                          |+
              |__X___|          :  _______  __   __ : _.-" ;  |            [             |+
              |      |         :: |       ||  | |  |::),.-'   |        ----------        |+
              |  |   |        ::: |    ___||  |_|  |:::/      \        \________/        /+
              |  |  _|        ::: |   |___ |       |:::        `-..__________________..-' +=
              |  |  |         ::: |    ___||_     _|:::               |    | |    |
              |  |  |         ::: |   |      |   |  :::               |    | |    |
              (  (  |          :: |___|      |___|  ::                |    | |    |
              |  |  |           :    `fyTokenOut`   :                 T----T T----T
              |  |  |            `:::::::::::::::::'             _..._L____J L____J _..._
             _|  |  |              `-:::::::::::-'             .` "-. `%   | |    %` .-" `.
            (_____[__)                `'''''''`               /      \    .: :.     /      \
                                                              '-..___|_..=:` `-:=.._|___..-'
 */
    /// Buy fyToken for base
    /// The trader needs to have called `base.approve`
    /// @param to Wallet receiving the fyToken being bought
    /// @param fyTokenOut Amount of fyToken being bought that will be deposited in `to` wallet
    /// @param max Maximum amount of base token that will be paid for the trade
    /// @return Amount of base that will be taken from caller's wallet
    function buyFYToken(
        address to,
        uint128 fyTokenOut,
        uint128 max
    ) external override returns (uint128) {
        // Calculate trade
        uint128 baseBalance = _getBaseBalance();
        (uint112 baseCached_, uint112 fyTokenCached_) = (baseCached, fyTokenCached);
        uint128 baseIn = _buyFYTokenPreview(fyTokenOut, baseCached_, fyTokenCached_);
        require(baseBalance - baseCached_ >= baseIn, "Pool: Not enough base token in");

        // Slippage check
        require(baseIn <= max, "Pool: Too much base token in");

        // Update TWAR
        _update(baseCached_ + baseIn, fyTokenCached_ - fyTokenOut, baseCached_, fyTokenCached_);

        // Transfer assets
        fyToken.safeTransfer(to, fyTokenOut);

        emit Trade(maturity, msg.sender, to, -(baseIn.i128()), fyTokenOut.i128());
        return baseIn;
    }

    /// Returns how much base would be required to buy `fyTokenOut` fyToken.
    /// @param fyTokenOut Amount of fyToken hypothetically desired.
    /// @return Amount of base hypothetically required.
    // function buyFYTokenPreview(uint128 fyTokenOut) external view override returns (uint128) { // todo
    function buyFYTokenPreview(uint128 fyTokenOut) external view override returns (uint128) {
        (uint112 baseCached_, uint112 fyTokenCached_) = (baseCached, fyTokenCached);
        return _buyFYTokenPreview(fyTokenOut, baseCached_, fyTokenCached_);
    }

    /// Returns how much base would be required to buy `fyTokenOut` fyToken.
    function _buyFYTokenPreview(
        uint128 fyTokenOut,
        uint128 baseBalance,
        uint128 fyTokenBalance
    ) private view beforeMaturity returns (uint128) {
        uint128 baseIn = YieldMath.sharesInForFYTokenOut(
            baseBalance * scaleFactor,
            fyTokenBalance * scaleFactor,
            fyTokenOut * scaleFactor,
            maturity - uint32(block.timestamp), // This can't be called after maturity
            ts,
            g1,
            _getC(),
            mu
        ) / scaleFactor;

        require(fyTokenBalance - fyTokenOut >= baseBalance + baseIn, "Pool: fyToken balance too low");

        return baseIn;
    }
}
