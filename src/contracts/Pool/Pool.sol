// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "./PoolImports.sol"; /*

TODO:

make an abstract Pool4626
then make a PoolYV inherits that and overwrites getC()
^^ maybe break up _getC into _getCurrentBasePrice and _getC
yieldcurity review

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
                    be cool, stay in pool         │     │    =======+
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

/// A Yieldspace AMM implementation for pools which provide liquidity and trading of fyTokens vs base tokens.
/// The base tokens in this implementation are erc4626 compliant tokenized vaults.
/// See whitepaper and derived formulas: https://hackmd.io/lRZ4mgdrRgOpxZQXqKYlFw
/// @title  Pool.sol
/// @dev Deploy pool with Yearn token and associated fyToken.
/// Uses 64.64 bit math under the hood for precision and reduced gas usage.
/// @author Orignal work by @alcueca. Adapted by @devtooligan.  Maths and whitepaper by @aniemburg.
contract Pool is PoolEvents, IYVPool, ERC20Permit, AccessControl {
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

    IYVToken public immutable base;
    IFYToken public immutable fyToken;

    int128 public immutable ts; //            1 / seconds in 10 years (64.64)
    uint32 public immutable maturity;
    uint96 public immutable scaleFactor; //   Used to scale up to 18 decimals (not 64.64)
    int128 public immutable mu; //            The normalization coefficient, the initial c value, in 64.64

    /* STORAGE
     *****************************************************************************************************************/

    // The following 4 vars use one storage slot and can be called with getCache()
    uint16 public g1Fee; //                            Fee (in bps) To be used when buying fyToken
    uint104 private baseCached; //                     Base token reserves, cached
    uint104 private fyTokenCached; //                  fyToken reserves, cached
    uint32 private blockTimestampLast; //              block.timestamp of last time reserve caches were updated

    ///  __                            ___         ___  __       ___    __             __  ___
    /// /  ` |  |  |\/| |  | |     /\   |  | \  / |__  |__)  /\   |  | /  \ |     /\  /__`  |
    /// \__, \__/  |  | \__/ |___ /~~\  |  |  \/  |___ |  \ /~~\  |  | \__/ |___ /~~\ .__/  |
    /// a LAGGING, time weighted sum of the fyToken:base reserves ratio:
    ///
    /// The current reserves ratio is not included in cumulativeRatioLast.
    /// Only when the reserves ratio change again in the future, will the current ratio get applied.
    /// See _update() for more explanation on how this number is updated.
    ///
    /// @dev Footgun alert!  Be careful, this number is probably not what you need and should normally be considered
    /// along with blockTimestampLast. Use currentCumulativeRatio() for consumption as a TWAR observation.
    /// @return a fixed point factor with 27 decimals (ray).
    // TODO: consider changing visibility private to reduce risk of misuse
    uint256 public cumulativeRatioLast;

    /* CONSTRUCTOR
     *****************************************************************************************************************/

    constructor(
        address base_,
        address fyToken_,
        int128 ts_,
        uint16 g1Fee_
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

        setFees(g1Fee_);

        scaleFactor = uint96(10**(18 - uint96(decimals)));

        if ((mu = _getC()) == 0) {
            revert MuZero();
        }

    }

    /* LIQUIDITY FUNCTIONS

        ┌─────────────────────────────────────────────────┐
        │  mint, new life. gm!                            │
        │  buy, sell, mint more, trade, trade -- stop     │
        │  mature, burn. gg~                              │
        │                                                 │
        │ "Watashinojinsei (My Life)" - haiku by Poolie   │
        └─────────────────────────────────────────────────┘

     *****************************************************************************************************************/

    /*mint
                                                                                              v
         ___                                                                           \            /
         |_ \_/                   ┌───────────────────────────────┐
         |   |                    │                               │                 `    _......._     '   gm!
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
                                  │                               │                 `    _......._     '   gm!
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
    /// The amount of liquidity tokens is calculated from the amount of fyTokenToBuy from the pool,
    /// plus the amount of extra, unaccounted for fyToken in this contract.
    /// The base tokens also need to be present in this contract, unaccounted for.
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
        (uint16 g1Fee_, uint104 baseCached_, uint104 fyTokenCached_, ) = getCache();
        uint256 realFYTokenCached_ = fyTokenCached_ - supply; // The fyToken cache includes the virtual fyToken, equal to the supply
        // uint256 fyTokenBalance = fyToken.balanceOf(address(this));
        uint256 baseAvailable = base.balanceOf(address(this)) - baseCached_;

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
        } else if (realFYTokenCached_ == 0) {
            // Edge case, no fyToken in the Pool after initialization
            baseIn = baseAvailable;
            tokensMinted = (supply * baseIn) / baseCached_;
        } else {
            // There is an optional virtual trade before the mint
            uint256 baseToSell;
            if (fyTokenToBuy != 0) {
                baseToSell = _buyFYTokenPreview(fyTokenToBuy.u128(), baseCached_, fyTokenCached_, _computeG1(g1Fee_));
            }

            // We use all the available fyTokens, plus a virtual trade if it happened, surplus is in base tokens
            fyTokenIn = fyToken.balanceOf(address(this)) - realFYTokenCached_;
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
                )   )\/ ( \/(( (    gg            ___
                ((  /     ))\))))\      ┌~~~~~~►  |_ \_/
                 )\(          |  )      │         |   |
                /:  | __    ____/:      │
                ::   / /   / __ \::  ───┤
                ::  / /   / /_/ /::     │
                :: / /___/ ____/ ::     └~~~~~~►  B A S E
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
                 )   )\/ ( \/(( (    gg
                 ((  /     ))\))))\
                  )\(          |  )
                /:  | __    ____/:
                ::   / /   / __ \::   ~~~~~~~►   B A S E
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
        (uint16 g1Fee_, uint104 baseCached_, uint104 fyTokenCached_, ) = getCache();

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
                    _computeG2(g1Fee_),
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
        (uint16 g1Fee_, uint104 baseCached_, uint104 fyTokenCached_, ) = getCache();
        uint104 baseBalance = _getBaseBalance();
        uint104 fyTokenBalance = _getFYTokenBalance();
        uint128 baseIn = baseBalance - baseCached_;
        uint128 fyTokenOut = _sellBasePreview(baseIn, baseCached_, fyTokenBalance, _computeG1(g1Fee_));

        // Slippage check
        require(fyTokenOut >= min, "Pool: Not enough fyToken obtained");

        // Update TWAR
        _update(baseBalance, fyTokenBalance - fyTokenOut, baseCached_, fyTokenCached_);

        // Transfer assets
        fyToken.safeTransfer(to, fyTokenOut);

        emit Trade(maturity, msg.sender, to, -(baseIn.i128()), fyTokenOut.i128());
        return fyTokenOut;
    }

    /// Returns how much fyToken would be obtained by selling `baseIn` base
    /// @param baseIn Amount of base hypothetically sold.
    /// @return Amount of fyToken hypothetically bought.
    function sellBasePreview(uint128 baseIn) external view override returns (uint128) {
        (uint16 g1Fee_, uint104 baseCached_, uint104 fyTokenCached_, ) = getCache();
        return _sellBasePreview(baseIn, baseCached_, fyTokenCached_, _computeG1(g1Fee_));
    }

    /// Returns how much fyToken would be obtained by selling `baseIn` base
    function _sellBasePreview(
        uint128 baseIn,
        uint104 baseBalance,
        uint104 fyTokenBalance,
        int128 g1_
    ) private view beforeMaturity returns (uint128) {
        uint128 fyTokenOut = YieldMath.fyTokenOutForSharesIn(
            baseBalance * scaleFactor,
            fyTokenBalance * scaleFactor,
            baseIn * scaleFactor,
            maturity - uint32(block.timestamp), // This can't be called after maturity
            ts,
            g1_,
            _getC(),
            mu
        ) / scaleFactor;

        require(fyTokenBalance - fyTokenOut >= baseBalance + baseIn, "Pool: fyToken balance too low");

        return fyTokenOut;
    }

    /* buyBase

                         I want to buy `uint128 tokenOut` worth of base tokens.
             _______     I've already approved fyTokens to the pool so take what you need for the swap.
            /   GUY \         .:::::::::::::::::.
     (^^^|   \===========    :  _______  __   __ :                 ┌─────────┐
      \(\/    | _  _ |      :: |       ||  | |  |::                │no       │
       \ \   (. o  o |     ::: |    ___||  |_|  |:::               │lifeguard│
        \ \   |   ~  |     ::: |   |___ |       |:::               └─┬─────┬─┘       ==+
        \  \   \ == /      ::: |    ___||_     _|:::    can          │     │    =======+
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
        (uint16 g1Fee_, uint104 baseCached_, uint104 fyTokenCached_, ) = getCache();
        uint128 fyTokenIn = _buyBasePreview(tokenOut, baseCached_, fyTokenCached_, _computeG2(g1Fee_));
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
        (uint16 g1Fee_, uint104 baseCached_, uint104 fyTokenCached_, ) = getCache();
        return _buyBasePreview(tokenOut, baseCached_, fyTokenCached_, _computeG2(g1Fee_));
    }

    /// Returns how much fyToken would be required to buy `tokenOut` base.
    function _buyBasePreview(
        uint128 tokenOut,
        uint104 baseBalance,
        uint104 fyTokenBalance,
        int128 g2_
    ) private view beforeMaturity returns (uint128) {
        return
            YieldMath.fyTokenInForSharesOut(
                baseBalance * scaleFactor,
                fyTokenBalance * scaleFactor,
                tokenOut * scaleFactor,
                maturity - uint32(block.timestamp), // This can't be called after maturity
                ts,
                g2_,
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
        \  \   \ == /      ::: |    ___||_     _|:::   I think so    │     │    =======+
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
        (uint16 g1Fee_, uint104 baseCached_, uint104 fyTokenCached_, ) = getCache();
        uint104 fyTokenBalance = _getFYTokenBalance();
        uint104 baseBalance = _getBaseBalance();
        uint128 fyTokenIn = fyTokenBalance - fyTokenCached_;
        uint128 baseOut = _sellFYTokenPreview(fyTokenIn, baseCached_, fyTokenCached_, _computeG2(g1Fee_));

        // Slippage check
        require(baseOut >= min, "Pool: Not enough base obtained");

        // Update TWAR
        _update(baseBalance - baseOut, fyTokenBalance, baseCached_, fyTokenCached_);

        // Transfer assets
        base.safeTransfer(to, baseOut);

        emit Trade(maturity, msg.sender, to, baseOut.i128(), -(fyTokenIn.i128()));
        return baseOut;
    }

    /// Returns how much base would be obtained by selling `fyTokenIn` fyToken.
    /// @param fyTokenIn Amount of fyToken hypothetically sold.
    /// @return Amount of base hypothetically bought.
    function sellFYTokenPreview(uint128 fyTokenIn) public view returns (uint128) {
        (uint16 g1Fee_, uint104 baseCached_, uint104 fyTokenCached_, ) = getCache();
        return _sellFYTokenPreview(fyTokenIn, baseCached_, fyTokenCached_, _computeG2(g1Fee_));
    }

    /// Returns how much base would be obtained by selling `fyTokenIn` fyToken.
    function _sellFYTokenPreview(
        uint128 fyTokenIn,
        uint104 baseBalance,
        uint104 fyTokenBalance,
        int128 g2_
    ) private view beforeMaturity returns (uint128) {
        return
            YieldMath.sharesOutForFYTokenIn(
                baseBalance * scaleFactor,
                fyTokenBalance * scaleFactor,
                fyTokenIn * scaleFactor,
                maturity - uint32(block.timestamp), // This can't be called after maturity
                ts,
                g2_,
                _getC(),
                mu
            ) / scaleFactor;
    }

    /*buyFYToken

                         I want to buy `uint128 fyTokenOut` worth of fyTokens.
             _______     I've approved base for you to take what you need for the swap.
            /   GUY \                                                 ┌─────────┐
     (^^^|   \===========  ┌──────────────┐                           │no       │
      \(\/    | _  _ |     │$            $│                           │lifeguard│
       \ \   (. o  o |     │ ┌────────────┴─┐                         └─┬─────┬─┘       ==+
        \ \   |   ~  |     │ │$            $│           ok, Guy!        │     │    =======+
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
        (uint16 g1Fee_, uint104 baseCached_, uint104 fyTokenCached_, ) = getCache();
        uint128 baseIn = _buyFYTokenPreview(fyTokenOut, baseCached_, fyTokenCached_, _computeG1(g1Fee_));
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
    function buyFYTokenPreview(uint128 fyTokenOut) external view override returns (uint128) {
        (uint16 g1Fee_, uint104 baseCached_, uint104 fyTokenCached_, ) = getCache();
        return _buyFYTokenPreview(fyTokenOut, baseCached_, fyTokenCached_, _computeG1(g1Fee_));
    }

    /// Returns how much base would be required to buy `fyTokenOut` fyToken.
    function _buyFYTokenPreview(
        uint128 fyTokenOut,
        uint128 baseBalance,
        uint128 fyTokenBalance,
        int128 g1_
    ) private view beforeMaturity returns (uint128) {
        uint128 baseIn = YieldMath.sharesInForFYTokenOut(
            baseBalance * scaleFactor,
            fyTokenBalance * scaleFactor,
            fyTokenOut * scaleFactor,
            maturity - uint32(block.timestamp), // This can't be called after maturity
            ts,
            g1_,
            _getC(),
            mu
        ) / scaleFactor;

        require(fyTokenBalance - fyTokenOut >= baseBalance + baseIn, "Pool: fyToken balance too low");

        return baseIn;
    }

    /* BALANCES MANAGEMENT AND ADMINISTRATIVE FUNCTIONS
     *****************************************************************************************************************/
    /*
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

    /// Returns the base balance.
    /// @return The current balance of the pool's base tokens.
    function getBaseBalance() public view override returns (uint104) {
        return _getBaseBalance();
    }

    /// Returns the base token current price.
    /// @return The price of 1 base token in terms of its underlying as fp18 cast as uint256.
    function getBaseCurrentPrice() public view returns (uint256) {
        return base.pricePerShare();
    }

    /// The "virtual" fyToken balance, which is the actual balance plus the pool token supply.
    /// @dev For more explanation about using the LP tokens as part of the virtual reserves see:
    /// https://hackmd.io/lRZ4mgdrRgOpxZQXqKYlFw
    /// @return The current balance of the pool's fyTokens plus the current balance of the pool's
    /// total supply of LP tokens as a uint104
    function getFYTokenBalance() public view override returns (uint104) {
        return _getFYTokenBalance();
    }

    /// Returns the all storage vars except for cumulativeRatioLast
    /// @return g1Fee.
    /// @return Cached base token balance.
    /// @return Cached virtual FY token balance which is the actual balance plus the pool token supply.
    /// @return Timestamp that balances were last cached.
    //TODO: Should we replace this with a struct?
    function getCache()
        public
        view
        returns (
            uint16,
            uint104,
            uint104,
            uint32
        )
    {
        return (g1Fee, baseCached, fyTokenCached, blockTimestampLast);
    }

    /// Calculates cumulative ratio as of current timestamp.  Can be consumed for TWAR observations.
    /// @return currentCumulativeRatio_ is the cumulative ratio up to the current timestamp as ray.
    /// @return blockTimestampCurrent is the current block timestamp that the currentCumulativeRatio was computed with.
    function currentCumulativeRatio()
        external
        view
        returns (uint256 currentCumulativeRatio_, uint256 blockTimestampCurrent)
    {
        blockTimestampCurrent = block.timestamp;
        uint256 timeElapsed;
        unchecked {
            timeElapsed = blockTimestampCurrent - blockTimestampLast;
        }

        // Multiply by 1e27 here so that r = t * y/x is a fixed point factor with 27 decimals
        currentCumulativeRatio_ =
            cumulativeRatioLast +
            ((uint256(fyTokenCached) * 1e27) * (timeElapsed)) /
            baseCached;
    }

    /// Retrieve any base tokens not accounted for in the cache
    /// @param to Address of the recipient of the base tokens.
    /// @return retrieved The amount of base tokens sent.
    function retrieveBase(address to) external override returns (uint128 retrieved) {
        // TODO: any interest in adding auth to these?
        // related: https://twitter.com/transmissions11/status/1505994136389754880?s=20&t=1H6gvzl7DJLBxXqnhTuOVw
        retrieved = _getBaseBalance() - baseCached; // Cache can never be above balances
        base.safeTransfer(to, retrieved);
        // Now the current balances match the cache, so no need to update the TWAR
    }

    /// Retrieve any fyTokens not accounted for in the cache
    /// @param to Address of the recipient of the fyTokens.
    /// @return retrieved The amount of fyTokens sent.
    function retrieveFYToken(address to) external override returns (uint128 retrieved) {
        // TODO: any interest in adding auth to these?
        // related: https://twitter.com/transmissions11/status/1505994136389754880?s=20&t=1H6gvzl7DJLBxXqnhTuOVw
        retrieved = _getFYTokenBalance() - fyTokenCached; // Cache can never be above balances
        fyToken.safeTransfer(to, retrieved);
        // Now the balances match the cache, so no need to update the TWAR
    }

    /// Updates the cache to match the actual balances.
    function sync() external {
        _update(_getBaseBalance(), _getFYTokenBalance(), baseCached, fyTokenCached);
    }

    /// Sets g1 numerator and denominator
    /// @dev These numbers are converted to 64.64 and used to calculate g1 by dividing them, or g2 from 1/g1
    function setFees(uint16 g1Fee_) public auth {
        if (g1Fee_ > 10000) {
            revert InvalidFee();
        }
        g1Fee = g1Fee_;
        emit FeesSet(g1Fee_);
    }

    /// Returns the ratio of net proceeds after fees, for buying fyToken
    function _computeG1(uint16 g1Fee_) internal pure returns (int128) {
        return uint256(10000 - g1Fee_).fromUInt().div(uint256(10000).fromUInt());
    }

    /// Returns the ratio of net proceeds after fees, for selling fyToken
    function _computeG2(uint16 g1Fee_) internal pure returns (int128) {
        // Divide 1 (64.64) by g1
        return int128(YieldMath.ONE).div(uint256(10000 - g1Fee_).fromUInt().div(uint256(10000).fromUInt()));
    }

    /// Returns the base balance
    function _getBaseBalance() internal view returns (uint104) {
        return uint104(base.balanceOf(address(this)));
        // return base.balanceOf(address(this)).u104();  TODO: Implement cast104
    }

    /// Returns the base current price
    function _getBasePrice() internal view virtual returns (uint256) {
        return base.pricePerShare() * scaleFactor;
    }

    /// Returns the c based on the current price
    function _getC() internal view returns (int128) {
        return ((_getBasePrice()).fromUInt()).div(uint256(1e18).fromUInt());
    }

    /// Returns the "virtual" fyToken balance, which is the real balance plus the pool token supply.
    function _getFYTokenBalance() internal view returns (uint104) {
        return uint104((fyToken.balanceOf(address(this)) + _totalSupply));
        // return (fyToken.balanceOf(address(this)) + _totalSupply).u104();  TODO: Implement cast104
    }

    /// Update cached values and, on the first call per block, cumulativeRatioLast.
    /// NOTE: cumulativeRatioLast is a LAGGING, time weighted sum of the reserves ratio which is updated as follows:
    ///
    ///   cumRatLast += old fyTokenReserves / old baseReserves * seconds elapsed since blockTimestampLast
    ///
    /// Example:
    ///   First mint creates a ratio of 1:1.
    ///   300 seconds later a trade occurs:
    ///     - cumRatLast is updated: 0 + 1/1 * 300 == 300
    ///     - baseCached and fyTokenCached are updated with the new reserves amounts.
    ///     - This causes the ratio to skew to 1.1 / 1.
    ///   200 seconds later another trade occurs:
    ///     - NOTE: During this 200 seconds, cumRatLast == 300, which represents the "last" updated amount.
    ///     - cumRatLast is updated: 300 + 1.1 / 1 * 200 == 520
    ///     - baseCached and fyTokenCached updated accordingly...etc.
    ///
    function _update(
        uint128 baseBalance,
        uint128 fyBalance,
        uint104 baseCached_,
        uint104 fyTokenCached_
    ) private {
        require(baseBalance <= type(uint104).max && fyBalance <= type(uint104).max, "u104 overflow"); //  TODO: add u104 to casting lib

        // No need to update and spend gas on SSTORE if reserves haven't changed.
        if (baseBalance == baseCached_ && fyBalance == fyTokenCached_) return;

        uint32 blockTimestamp = uint32(block.timestamp);
        uint32 timeElapsed;
        timeElapsed = blockTimestamp - blockTimestampLast; // underflow is desired //TODO: UniV2 said "overflow is desired" but not sure why

        uint256 oldCumulativeRatioLast = cumulativeRatioLast;
        uint256 newCumulativeRatioLast = oldCumulativeRatioLast;
        if (timeElapsed > 0 && fyTokenCached_ > 0 && baseCached_ > 0) {
            // Multiply by 1e27 here so that r = t * y/x is a fixed point factor with 27 decimals
            uint256 scaledFYTokenCached = uint256(fyTokenCached_) * 1e27;
            newCumulativeRatioLast += (scaledFYTokenCached * timeElapsed) / baseCached_;
        }

        // TODO: Consider not udpating these two if ratio hasn't changed to save gas on SSTORE.
        blockTimestampLast = blockTimestamp;
        cumulativeRatioLast = newCumulativeRatioLast;

        // Update the reserves caches
        baseCached = uint104(baseBalance); //  TODO: add u104 to casting lib
        fyTokenCached = uint104(fyBalance); // TODO: add u104 to casting lib

        emit Sync(baseCached, fyTokenCached, newCumulativeRatioLast);
    }
}
