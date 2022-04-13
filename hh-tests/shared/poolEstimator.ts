import { BigNumber, BigNumberish } from 'ethers'
import { IERC20 } from '../../typechain/IERC20'
import { YvTokenMock as YvToken } from '../../typechain/YvTokenMock'
import { Pool } from '../../typechain/Pool'
import { mint, burn, sellBase, sellFYToken, buyBase, buyFYToken, mintWithBase, burnForBase } from './yieldspace'
import { ethers } from 'hardhat'
import { Decimal } from 'decimal.js';

import { secondsInTenYears } from './constants'
const ts = new Decimal(1 / secondsInTenYears.toNumber()); // inv of seconds in 4 years
const g1 = new Decimal(950 / 1000);
const g2 = new Decimal(1000 / 950);


async function currentTimestamp() {
  return (await ethers.provider.getBlock('latest')).timestamp
}

export class PoolEstimator {
  pool: Pool
  base: YvToken
  fyToken: IERC20

  constructor(pool: Pool, base: YvToken, fyToken: IERC20) {
    this.pool = pool
    this.base = base
    this.fyToken = fyToken
  }

  public static async setup(pool: Pool): Promise<PoolEstimator> {
    const base = (await ethers.getContractAt('YvTokenMock', await pool.base())) as YvToken
    const fyToken = (await ethers.getContractAt('IERC20', await pool.fyToken())) as IERC20
    return new PoolEstimator(pool, base, fyToken)
  }

  public async sellBase(): Promise<BigNumber> {
    return sellBase(
      await this.pool.getBaseBalance(),
      await this.pool.getFYTokenBalance(),
      (await this.pool.getBaseBalance()).sub((await this.pool.getCache())[0]),
      BigNumber.from(await this.pool.maturity()).sub(await currentTimestamp()),
      await this.pool.scaleFactor()
    )
  }

  public async sellFYToken(): Promise<BigNumber> {
    return sellFYToken(
      await this.pool.getBaseBalance(),
      await this.pool.getFYTokenBalance(),
      (await this.pool.getFYTokenBalance()).sub((await this.pool.getCache())[1]),
      BigNumber.from(await this.pool.maturity()).sub(await currentTimestamp()),
      await this.pool.scaleFactor()
    )
  }

  public async buyBase(tokenOut: BigNumberish): Promise<BigNumber> {
    return buyBase(
      await this.pool.getBaseBalance(),
      await this.pool.getFYTokenBalance(),
      BigNumber.from(tokenOut),
      BigNumber.from(await this.pool.maturity()).sub(await currentTimestamp()),
      await this.pool.scaleFactor()
    )
  }

  // public async buyFYToken(tokenOut: BigNumberish): Promise<BigNumber> {
  //   return buyFYToken(
  //     await this.pool.getBaseBalance(), // Z
  //     await this.pool.getFYTokenBalance(), // Y
  //     BigNumber.from(tokenOut), // deltaY
  //     BigNumber.from("1"), // c
  //     BigNumber.from("1"), // mu
  //     BigNumber.from(await this.pool.maturity()).sub(await currentTimestamp()),
  //     BigNumber.from("1"), // ts
  //     BigNumber.from("1"), //gs
  //     18,
  //     // await this.pool.scaleFactor()
  //   )
  // }


  public async buyFYToken(tokenOut: BigNumberish): Promise<BigNumber> {
    return buyFYToken(
      await this.pool.getBaseBalance(),
      await this.pool.getFYTokenBalance(),
      BigNumber.from(tokenOut),
      await this.pool.getBaseCurrentPrice(),
      await this.pool.mu(),
      BigNumber.from(await this.pool.maturity()).sub(await currentTimestamp()),
      await this.pool.ts(),
      await this.pool.g1(),
      18
      // await this.pool.scaleFactor()
    )
  }

  public async mint(input: BigNumber): Promise<[BigNumber, BigNumber]> {
    return mint(
      await this.base.balanceOf(this.pool.address),
      await this.fyToken.balanceOf(this.pool.address),
      await this.pool.totalSupply(),
      input
    )
  }

  public async burn(lpTokens: BigNumber): Promise<[BigNumber, BigNumber]> {
    return burn(
      await this.base.balanceOf(this.pool.address),
      await this.fyToken.balanceOf(this.pool.address),
      await this.pool.totalSupply(),
      lpTokens
    )
  }

  public async mintWithBase(fyToken: BigNumber): Promise<[BigNumber, BigNumber]> {
    return mintWithBase(
      await this.base.balanceOf(this.pool.address),
      await this.pool.getFYTokenBalance(),
      await this.fyToken.balanceOf(this.pool.address),
      await this.pool.mu(),
      await this.pool.getBaseCurrentPrice(),
      fyToken,
      BigNumber.from(await this.pool.maturity()).sub(await currentTimestamp()),
      await this.pool.ts(),
      await this.pool.g1(),
      new Decimal(18)
      // await this.pool.scaleFactor()
    )
  }

  // public async mintWithBase(fyToken: BigNumber): Promise<[BigNumber, BigNumber]> {
  //   return mintWithBase(
  //     await this.base.balanceOf(this.pool.address),
  //     await this.pool.getFYTokenBalance(),
  //     await this.fyToken.balanceOf(this.pool.address),
  //     await this.pool.mu(),
  //     await this.pool.getBaseCurrentPrice(),
  //     await this.pool.totalSupply(),
  //     fyToken,
  //     BigNumber.from(await this.pool.maturity()).sub(await currentTimestamp()),
  //     await this.pool.scaleFactor()
  //   )
  // }

  public async burnForBase(lpTokens: BigNumber): Promise<BigNumber> {
    return burnForBase(
      await this.base.balanceOf(this.pool.address),
      await this.pool.getFYTokenBalance(),
      await this.fyToken.balanceOf(this.pool.address),
      await this.pool.totalSupply(),
      lpTokens,
      BigNumber.from(await this.pool.maturity()).sub(await currentTimestamp()),
      await this.pool.scaleFactor()
    )
  }
}
