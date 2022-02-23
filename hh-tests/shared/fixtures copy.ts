import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import { BaseProvider } from '@ethersproject/providers'

import { constants, id } from '@yield-protocol/utils-v2'
const { DAI, ETH, USDC, THREE_MONTHS, MAX256 } = constants
const MAX = MAX256

import { YieldMath } from '../../typechain/YieldMath'
import { Pool } from '../../typechain/Pool'
import { ERC20Mock as ERC20 } from '../../typechain/ERC20Mock'
import { YvTokenMock as YvToken } from '../../typechain/YvTokenMock'
import { FYTokenMock as FYToken } from '../../typechain/FYTokenMock'
import { ethers } from 'hardhat'
import { BigNumber } from 'ethers'
import { ts, g1, g2, YVDAI, YVUSDC } from './constants'

export class YieldSpaceEnvironment {
    owner: SignerWithAddress
    bases: Map<string, ERC20>
    yvBases: Map<string, YvToken>
    fyTokens: Map<string, FYToken>
    pools: Map<string, Map<string, Pool>>

    constructor(
        owner: SignerWithAddress,
        yvBases: Map<string, YvToken>,
        fyTokens: Map<string, FYToken>,
        pools: Map<string, Map<string, Pool>>
    ) {
        this.owner = owner
        this.yvBases = yvBases
        this.fyTokens = fyTokens
        this.pools = pools
    }

    // Set up a test environment with pools according to the cartesian product of the base ids and the fyToken ids
    public static async setup(
        owner: SignerWithAddress,
        yvBaseIds: Array<string>,
        maturityIds: Array<string>,
        initialBase: BigNumber
    ) {
        const ownerAdd = await owner.getAddress()

        let yieldMathLibrary: YieldMath
        const initialFYToken = initialBase.div(9)
        const yvBases: Map<string, YvToken> = new Map()
        const bases: Map<string, ERC20> = new Map()
        const fyTokens: Map<string, FYToken> = new Map()
        const pools: Map<string, Map<string, Pool>> = new Map()
        const now = (await ethers.provider.getBlock('latest')).timestamp
        let count: number = 1

        const WETH9Factory = await ethers.getContractFactory('WETH9Mock')
        const weth9 = (((await WETH9Factory.deploy()) as unknown) as unknown) as ERC20
        await weth9.deployed()

        const DaiFactory = await ethers.getContractFactory('DaiMock')
        const dai = (((await DaiFactory.deploy('DAI', 'DAI')) as unknown) as unknown) as ERC20
        await dai.deployed()

        const YvDaiFactory = await ethers.getContractFactory('YvTokenMock')
        const yvDai = (((await YvDaiFactory.deploy('YVDAI', 'YVDAI', 18, dai.address)) as unknown) as unknown) as YvToken
        await yvDai.deployed()

        const USDCFactory = await ethers.getContractFactory('USDCMock')
        const usdc = (((await USDCFactory.deploy('USDC', 'USDC')) as unknown) as unknown) as ERC20
        await usdc.deployed()

        const YvUsdcFactory = await ethers.getContractFactory('YvTokenMock')
        const yvUsdc = (((await YvUsdcFactory.deploy('YVUSDC', 'YVUSDC', 18, usdc.address)) as unknown) as unknown) as YvToken
        await yvUsdc.deployed()

        const FYTokenFactory = await ethers.getContractFactory('FYTokenMock')
        const YieldMathFactory = await ethers.getContractFactory('YieldMath')
        yieldMathLibrary = ((await YieldMathFactory.deploy()) as unknown) as YieldMath
        await yieldMathLibrary.deployed()

        const PoolFactory = await ethers.getContractFactory('Pool', {
            libraries: {
                YieldMath: yieldMathLibrary.address,
            },
        })

        // add bases
        const yvBasesMapping = {
            [YVDAI]: yvDai,
            [YVUSDC]: yvUsdc,
        }
        for (let baseId of yvBaseIds) {
            const yvBase = yvBasesMapping[baseId]
            if (!yvBase) {
                throw("Base not found")
            }
            yvBases.set(baseId, yvBase)
        }

        // add WETH to bases
        bases.set(ETH, weth9)
        const baseIds = [ETH]

        // add Dai to bases
        bases.set(DAI, dai)
        baseIds.unshift(DAI)

        // add USDC to bases
        bases.set(USDC, usdc)
        baseIds.unshift(USDC)

        for (let baseId of baseIds) {
            const base = bases.get(baseId) as ERC20
            const fyTokenPoolPairs: Map<string, Pool> = new Map()
            pools.set(baseId, fyTokenPoolPairs)

            for (let maturityId of maturityIds) {
                const fyTokenId = baseId + '-' + maturityId

                // deploy fyToken
                const maturity = now + THREE_MONTHS * count++ // We are just assuming that the maturities are '3M', '6M', '9M' and so on
                const fyToken = ((await FYTokenFactory.deploy(base.address, maturity)) as unknown) as FYToken
                await fyToken.deployed()
                fyTokens.set(fyTokenId, fyToken)

                // deploy base/fyToken pool
                const pool = ((await PoolFactory.deploy(base.address, fyToken.address, ts, g1, g2)) as unknown) as Pool
                fyTokenPoolPairs.set(fyTokenId, pool)

                // init pool
                if (initialBase !== BigNumber.from(0)) {
                    if (baseId === ETH) {
                        break // TODO: Fix when we can give `initialBase` ether to the deployer
                    } else {
                        await base.mint(pool.address, initialBase)
                    }
                    await pool.mint(ownerAdd, ownerAdd, 0, MAX)

                    // skew pool to 5% interest rate
                    await fyToken.mint(pool.address, initialFYToken)
                    await pool.sync()
                }
            }
        }

        return new YieldSpaceEnvironment(owner, bases, fyTokens, pools)
    }
}
