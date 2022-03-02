import { ethers, BigNumber } from 'ethers';
import { secondsInTenYears, ts as tsBn, g1 as g1Bn, g2 as g2Bn} from './constants'
import { Decimal } from 'decimal.js';

Decimal.set({ precision: 64 });

/* constants exposed for export */
export const ZERO_DEC: Decimal = new Decimal(0);
export const ONE_DEC: Decimal = new Decimal(1);
export const TWO_DEC: Decimal = new Decimal(2);
export const SECONDS_PER_YEAR: number = (365 * 24 * 60 * 60);

/* locally used constants */
const ZERO = ZERO_DEC;
const ONE = ONE_DEC;
const TWO = TWO_DEC;
const ts = new Decimal(1 / secondsInTenYears.toNumber()); // inv of seconds in 4 years
const g1 = new Decimal(950 / 1000);
const g2 = new Decimal(1000 / 950);
const precisionFee = new Decimal(1000000000000);

/** *************************
 Support functions
 *************************** */

/**
 * specific Yieldspace helper functions
 * */
const _computeA = (
  timeToMaturity: BigNumber | string,
  ts: BigNumber | string,
  g: BigNumber | string
): [Decimal, Decimal] => {
  const timeTillMaturity_ = new Decimal(timeToMaturity.toString());
  // console.log( new Decimal(BigNumber.from(g).toString()).div(2 ** 64).toString() )

  const _g = new Decimal(BigNumber.from(g).toString()).div(2 ** 64);
  const _ts = new Decimal(BigNumber.from(ts).toString()).div(2 ** 64);

  // t = ts * timeTillMaturity
  const t = _ts.mul(timeTillMaturity_);
  // a = (1 - gt)
  const a = ONE.sub(_g.mul(t));
  const invA = ONE.div(a);
  return [a, invA]; /* returns a and inverse of a */
};

/**
 * Convert a bignumber with any decimal to a bn with decimal of 18
 * @param x bn to convert.
 * @param decimals of the current bignumber
 * @returns BigNumber
 */
export const decimalNToDecimal18 = (x: BigNumber, decimals: number): BigNumber =>
  BigNumber.from(x.toString() + '0'.repeat(18 - decimals));

/**
 * Convert a decimal18 to a bn of any decimal
 * @param x 18 decimal to reduce
 * @param decimals required
 * @returns BigNumber
 */
export const decimal18ToDecimalN = (x: BigNumber, decimals: number): BigNumber => {
  const str = x.toString();
  const first = str.slice(0, str.length - (18 - decimals));
  return BigNumber.from(first || 0); // zero if slice removes more than the number of decimals
};

/**
 * @param { BigNumber | string } multiplicant
 * @param { BigNumber | string } multiplier
 * @param { string } precisionDifference  // Difference between multiplicant and multiplier precision (eg. wei vs ray '1e-27' )
 * @returns { string } in decimal precision of the multiplicant
 */
export const mulDecimal = (
  multiplicant: BigNumber | string,
  multiplier: BigNumber | string,
  precisionDifference: string = '1', // DEFAULT = 1 (same precision)
): string => {
  const multiplicant_ = new Decimal(multiplicant.toString());
  const multiplier_ = new Decimal(multiplier.toString());
  const _preDif = new Decimal(precisionDifference.toString());
  const _normalisedMul = multiplier_.mul(_preDif);
  return multiplicant_.mul(_normalisedMul).toFixed();
};

/**
 * @param  { BigNumber | string } numerator
 * @param { BigNumber | string } divisor
 * @param { BigNumber | string } precisionDifference // Difference between multiplicant and mulitplier precision (eg. wei vs ray '1e-27' )
 * @returns { string } in decimal precision of the numerator
 */
export const divDecimal = (
  numerator: BigNumber | string,
  divisor: BigNumber | string,
  precisionDifference: string = '1', // DEFAULT = 1 (same precision)
): string => {
  const numerator_ = new Decimal(numerator.toString());
  const divisor_ = new Decimal(divisor.toString());
  const _preDif = new Decimal(precisionDifference.toString());
  const _normalisedDiv = divisor_.mul(_preDif);
  return numerator_.div(_normalisedDiv).toFixed();
};

/**
 * @param { BigNumber | string } value
 * @returns { string }
 */
export const floorDecimal = (value: BigNumber | string): string => Decimal.floor(value.toString()).toFixed();

/**
 * @param { Decimal } value
 * @returns { BigNumber }
 */
export const toBn = (value: Decimal): BigNumber => BigNumber.from(floorDecimal(value.toFixed()));

/**
 * @param { BigNumber | string } to unix time
 * @param { BigNumber | string } from  unix time *optional* default: now
 * @returns { string } as number seconds 'from' -> 'to'
 */
export const secondsToFrom = (
  to: BigNumber | string,
  from: BigNumber | string = BigNumber.from(Math.round(new Date().getTime() / 1000)), // OPTIONAL: FROM defaults to current time if omitted
): string => {
  const to_ = ethers.BigNumber.isBigNumber(to) ? to : BigNumber.from(to);
  const from_ = ethers.BigNumber.isBigNumber(from) ? from : BigNumber.from(from);
  return to_.sub(from_).toString();
};

/** *************************
 YieldSpace functions
 *************************** */


/**
 * @param { BigNumber | string } baseReserves
 * @param { BigNumber | string } fyTokenReserves
 * @param { BigNumber | string } totalSupply
 * @param { BigNumber | string } base
 * @returns {[BigNumber, BigNumber]}
 *
 * https://www.desmos.com/calculator/mllhtohxfx
 */
 export function mint(
  baseReserves: BigNumber | string,
  fyTokenReserves: BigNumber | string,
  totalSupply: BigNumber | string,
  base: BigNumber | string,
  fromBase: boolean = false
): [BigNumber, BigNumber] {
  const baseReserves_ = new Decimal(baseReserves.toString());
  const fyTokenReserves_ = new Decimal(fyTokenReserves.toString());
  const supply_ = new Decimal(totalSupply.toString());
  const base_ = new Decimal(base.toString());

  const m = fromBase ? supply_.mul(base_).div(baseReserves_) : supply_.mul(base_).div(fyTokenReserves_);
  const y = fromBase ? fyTokenReserves_.mul(m).div(supply_) : baseReserves_.mul(m).div(supply_);

  return [toBn(m), toBn(y)];
}

/**
 * @param { BigNumber | string } baseBalance
 * @param { BigNumber | string } fyTokenBalance
 * @param { BigNumber | string } totalSupply
 * @param lpTokens { BigNumber | string }
 * @returns {[BigNumber, BigNumber]}
 *
 * https://docs.google.com/spreadsheets/d/14K_McZhlgSXQfi6nFGwDvDh4BmOu6_Hczi_sFreFfOE/
 */
export function burn(
  baseBalance: BigNumber | string,
  fyTokenBalance: BigNumber | string,
  totalSupply: BigNumber | string,
  lpTokens: BigNumber | string,
): [BigNumber, BigNumber] {
  const Z = new Decimal(baseBalance.toString());
  const Y = new Decimal(fyTokenBalance.toString());
  const S = new Decimal(totalSupply.toString());
  const x = new Decimal(lpTokens.toString());
  const z = (x.mul(Z)).div(S);
  const y = (x.mul(Y)).div(S);
  return [toBn(z), toBn(y)];
}


/**
 * @param { BigNumber } baseReserves
 * @param { BigNumber } fyTokenReservesVirtual
 * @param { BigNumber } fyTokenReservesReal
 * @param { BigNumber | string } fyToken
 * @param { BigNumber | string } timeTillMaturity
 * @param { BigNumber | string } ts
 * @param { BigNumber | string } g1
 * @param { number } decimals
 *
 * @returns {[BigNumber, BigNumber]}
 */
 export function mintWithBase(
  baseReserves: BigNumber,
  fyTokenReservesVirtual: BigNumber,
  fyTokenReservesReal: BigNumber,
  mu: BigNumber | string,
  c: BigNumber | string,
  fyToken: BigNumber | string,
  timeTillMaturity: BigNumber | string,
  ts: BigNumber | string,
  g1: BigNumber | string,
  decimals: Decimal,
): [BigNumber, BigNumber] {
  const Z = new Decimal(baseReserves.toString());
  const YR = new Decimal(fyTokenReservesReal.toString());
  const supply = fyTokenReservesVirtual.sub(fyTokenReservesReal);
  const y = new Decimal(fyToken.toString());
  // buyFyToken:
  const z1 = new Decimal(
    buyFYToken(
      baseReserves,
      fyTokenReservesVirtual,
      fyToken,
      c,
      mu,
      timeTillMaturity,
      ts,
      g1,
      18).toString()
      // decimals).toString()
  );
  const Z2 = Z.add(z1); // Base reserves after the trade
  const YR2 = YR.sub(y); // FYToken reserves after the trade

  // Mint specifying how much fyToken to take in. Reverse of `mint`.
  const [minted, z2] = mint(toBn(Z2), toBn(YR2), supply, fyToken, false);

  return [minted, toBn(z1).add(z2)];
}

// /**
//  * @param { BigNumber | string } baseBalance
//  * @param { BigNumber | string } fyTokenBalanceVirtual
//  * @param { BigNumber | string } fyTokenBalanceReal
//  * @param { BigNumber | string } totalSupply
//  * @param { BigNumber | string } fyToken
//  * @param { BigNumber | string } timeTillMaturity
//  * @param { BigNumber | string } scaleFactor
//  * @returns {[BigNumber, BigNumber]}
//  */
// export function mintWithBase(
//   baseBalance: BigNumber | string,
//   fyTokenBalanceVirtual: BigNumber | string,
//   fyTokenBalanceReal: BigNumber | string,
//   mu: BigNumber | string,
//   c: BigNumber | string,
//   supply: BigNumber | string,
//   fyToken: BigNumber | string,
//   timeTillMaturity: BigNumber | string,
//   scaleFactor: BigNumber | string,
// ): [BigNumber, BigNumber] {
//   const Z = new Decimal(baseBalance.toString());
//   const YR = new Decimal(fyTokenBalanceReal.toString());
//   const S = new Decimal(supply.toString());
//   const y = new Decimal(fyToken.toString());

//   // buyFyToken:
//   /* console.log(`
//     base reserves: ${baseBalance}
//     fyToken virtual reserves: ${fyTokenBalanceVirtual}
//     fyTokenOut: ${fyToken}
//     timeTillMaturity: ${timeTillMaturity}
//     scaleFactor: ${scaleFactor}
//   `) */
//   const z1 = new Decimal(buyFYToken(
//     baseBalance,
//     fyTokenBalanceVirtual,
//     fyToken,
//     c,
//     mu,
//     timeTillMaturity,
//     ts,
//     g1,
//     scaleFactor).toString()
//   );
//   const Z2 = Z.add(z1)  // Base reserves after the trade
//   const YR2 = YR.sub(y) // FYToken reserves after the trade

//   // Mint specifying how much fyToken to take in. Reverse of `mint`.
//   const [m, z2] = mint(
//     Z2.floor().toFixed(),
//     YR2.floor().toFixed(),
//     supply,
//     fyToken,
//   )

//   /* console.log(`
//     Z_1: ${Z2.floor().toFixed()}
//     Y_1: ${YR2.floor().toFixed()}
//     z_1: ${z1}
//     y_1: ${fyToken}
//   `) */
//   return [m, toBn(z1).add(z2)];
// }

/**
 * @param { BigNumber | string } baseBalance
 * @param { BigNumber | string } fyTokenBalanceVirtual
 * @param { BigNumber | string } fyTokenBalanceReal
 * @param { BigNumber | string } totalSupply
 * @param { BigNumber | string } lpTokens
 * @param { BigNumber | string } timeTillMaturity
 * @param { BigNumber | string } scaleFactor
 * @returns { BigNumber }
 */
export function burnForBase(
  baseBalance: BigNumber,
  fyTokenBalanceVirtual: BigNumber,
  fyTokenBalanceReal: BigNumber,
  supply: BigNumber,
  lpTokens: BigNumber,
  timeTillMaturity: BigNumber,
  scaleFactor: BigNumber | string,
): BigNumber {
  // Burn FyToken
  const [z1, y] = burn(baseBalance, fyTokenBalanceReal, supply, lpTokens);
  // Sell FyToken for base
  const z2 = sellFYToken(baseBalance, fyTokenBalanceVirtual, y, timeTillMaturity, scaleFactor);
  const z1D = new Decimal(z1.toString());
  const z2D = new Decimal(z2.toString());
  return toBn(z1D.add(z2D));
}

/**
 * @param { BigNumber | string } baseBalance
 * @param { BigNumber | string } fyTokenBalance
 * @param { BigNumber | string } base
 * @param { BigNumber | string } timeTillMaturity
 * @param { BigNumber | string } scaleFactor
 * @param { boolean } withNoFee
 * @returns { BigNumber }
 */
export function sellBase(
  baseBalance: BigNumber | string,
  fyTokenBalance: BigNumber | string,
  base: BigNumber | string,
  timeTillMaturity: BigNumber | string,
  scaleFactor: BigNumber | string,
  withNoFee: boolean = false, // optional: default === false
): BigNumber {
  const scaleFactor_ = new Decimal(scaleFactor.toString());
  const baseBalance_ = (new Decimal(baseBalance.toString())).mul(scaleFactor_);
  const fyTokenBalance_ = (new Decimal(fyTokenBalance.toString())).mul(scaleFactor_);
  const timeTillMaturity_ = new Decimal(timeTillMaturity.toString());
  const x = (new Decimal(base.toString())).mul(scaleFactor_);

  const g = withNoFee ? ONE : g1;
  const t = ts.mul(timeTillMaturity_);
  const a = ONE.sub(g.mul(t));
  const invA = ONE.div(a);

  const Za = baseBalance_.pow(a);
  const Ya = fyTokenBalance_.pow(a);
  const Zxa = (baseBalance_.add(x)).pow(a);
  const sum = (Za.add(Ya)).sub(Zxa);
  const y = fyTokenBalance_.sub(sum.pow(invA));
  const yFee = y.sub(precisionFee);

  return toBn(yFee.div(scaleFactor_));
}

/**
 * @param { BigNumber | string } baseBalance
 * @param { BigNumber | string } fyTokenBalance
 * @param { BigNumber | string } fyToken
 * @param { BigNumber | string } timeTillMaturity
 * @param { BigNumber | string } scaleFactor
 * @param { boolean } withNoFee
 * @returns { BigNumber }
 */
export function sellFYToken(
  baseBalance: BigNumber | string,
  fyTokenBalance: BigNumber | string,
  fyToken: BigNumber | string,
  timeTillMaturity: BigNumber | string,
  scaleFactor: BigNumber | string,
  withNoFee: boolean = false, // optional: default === false
): BigNumber {
  const scaleFactor_ = new Decimal(scaleFactor.toString());
  const baseBalance_ = (new Decimal(baseBalance.toString())).mul(scaleFactor_);
  const fyTokenBalance_ = (new Decimal(fyTokenBalance.toString())).mul(scaleFactor_);
  const timeTillMaturity_ = new Decimal(timeTillMaturity.toString());
  const fyDai_ = (new Decimal(fyToken.toString())).mul(scaleFactor_);

  const g = withNoFee ? ONE : g2;
  const t = ts.mul(timeTillMaturity_);
  const a = ONE.sub(g.mul(t));
  const invA = ONE.div(a);

  const Za = baseBalance_.pow(a);
  const Ya = fyTokenBalance_.pow(a);
  const Yxa = (fyTokenBalance_.add(fyDai_)).pow(a);
  const sum = Za.add(Ya.sub(Yxa));
  const y = baseBalance_.sub(sum.pow(invA));
  const yFee = y.sub(precisionFee);

  return toBn(yFee.div(scaleFactor_));
}

/**
 * @param { BigNumber | string } baseBalance
 * @param { BigNumber | string } fyTokenBalance
 * @param { BigNumber | string } base
 * @param { BigNumber | string } timeTillMaturity
 * @param { BigNumber | string } scaleFactor
 * @param { boolean } withNoFee
 * @returns { BigNumber }
 */
export function buyBase(
  baseBalance: BigNumber | string,
  fyTokenBalance: BigNumber | string,
  base: BigNumber | string,
  timeTillMaturity: BigNumber | string,
  scaleFactor: BigNumber | string,
  withNoFee: boolean = false, // optional: default === false
): BigNumber {
  const scaleFactor_ = new Decimal(scaleFactor.toString());
  const baseBalance_ = (new Decimal(baseBalance.toString())).mul(scaleFactor_);
  const fyTokenBalance_ = (new Decimal(fyTokenBalance.toString())).mul(scaleFactor_);
  const timeTillMaturity_ = new Decimal(timeTillMaturity.toString());
  const x = (new Decimal(base.toString())).mul(scaleFactor_);

  const g = withNoFee ? ONE : g2;
  const t = ts.mul(timeTillMaturity_);
  const a = ONE.sub(g.mul(t));
  const invA = ONE.div(a);

  const Za = baseBalance_.pow(a);
  const Ya = fyTokenBalance_.pow(a);
  const Zxa = (baseBalance_.sub(x)).pow(a);
  const sum = (Za.add(Ya)).sub(Zxa);
  const y = (sum.pow(invA)).sub(fyTokenBalance_);
  const yFee = y.add(precisionFee);

  return toBn(yFee.div(scaleFactor_));
}

/**
 * Calculate the amount of variable yield base a user would have to pay for certain amount of fyToken.
 * sharesInForFYTokenOut
 * https://docs.google.com/spreadsheets/u/1/d/14K_McZhlgSXQfi6nFGwDvDh4BmOu6_Hczi_sFreFfOE/
 * @param { BigNumber | string } baseReserves
 * @param { BigNumber | string } fyTokenReserves
 * @param { BigNumber | string } fyToken
 * @param { BigNumber | string } c
 * @param { BigNumber | string } mu
 * @param { BigNumber | string } timeTillMaturity
 * @param { BigNumber | string } ts
 * @param { BigNumber | string } g1
 * @returns { BigNumber }
 *
 * y = fyToken
 * z = vyToken
 * x = Δy
 *
 *            (                 sum                                   )
 *              (     Za       )  ( Ya   )   (    Yxa     )             (   invA   )
 * dz = 1/μ * ( ( c/μ * μz^(1-t) + y^(1-t) - (y - x)^(1-t) ) / (c/μ) )^(1 / (1 - t)) - z
 */
export function buyFYToken(
  baseReserves: BigNumber | string, // z
  fyTokenReserves: BigNumber | string, // y
  fyToken: BigNumber | string,
  c: BigNumber | string,
  mu: BigNumber | string,
  timeTillMaturity: BigNumber | string,
  ts: BigNumber | string,
  g1: BigNumber | string,
  decimals: number // optional : default === 18
): BigNumber {
  /* convert to 18 decimals, if required */
  const baseReserves18 = decimalNToDecimal18(BigNumber.from(baseReserves), decimals);
  const fyTokenReserves18 = decimalNToDecimal18(BigNumber.from(fyTokenReserves), decimals);
  const fyToken18 = decimalNToDecimal18(BigNumber.from(fyToken), decimals);
  const c18 = decimalNToDecimal18(BigNumber.from(c), decimals);
  const mu18 = decimalNToDecimal18(BigNumber.from(mu), decimals);

  const baseReserves_ = new Decimal(baseReserves18.toString());
  const fyTokenReserves_ = new Decimal(fyTokenReserves18.toString());
  const fyToken_ = new Decimal(fyToken18.toString());
  const c_ = new Decimal(c18.toString()).div(new Decimal(1 * 10 ** 18)); // convert to ratio using 18 decimals (ie: 1.1)
  const mu_ = new Decimal(mu18.toString()).div(new Decimal(1 * 10 ** 18)); // convert to ratio using 18 decimals (ie: 1.1)

  const [a, invA] = _computeA(timeTillMaturity, ts, g1);

  const Za = c_.div(mu_).mul(mu_.mul(baseReserves_).pow(a));
  const Ya = fyTokenReserves_.pow(a);
  const Yxa = fyTokenReserves_.sub(fyToken_).pow(a);
  const sum = Za.add(Ya.sub(Yxa)).div(c_.div(mu_));
  const y = ONE.div(mu_).mul(sum.pow(invA)).sub(baseReserves_);

  const yFee = y.add(precisionFee);
  return yFee.isNaN() ? ethers.constants.Zero : decimal18ToDecimalN(toBn(yFee), decimals);
}

/**
 * @param { BigNumber | string } baseBalance
 * @param { BigNumber | string } fyTokenBalance
 * @param { BigNumber | string } fyToken
 * @param { BigNumber | string } timeTillMaturity
 * @param { BigNumber | string } scaleFactor
 * @returns { BigNumber }
 */
export function getFee(
  baseBalance: BigNumber | string,
  fyTokenBalance: BigNumber | string,
  fyToken: BigNumber | string,
  timeTillMaturity: BigNumber | string,
  scaleFactor: BigNumber | string,
): BigNumber {
  let fee_: Decimal = ZERO;
  const fyDai_: BigNumber = BigNumber.isBigNumber(fyToken) ? fyToken : BigNumber.from(fyToken);

  if (fyDai_.gte(ethers.constants.Zero)) {
    const daiWithFee: BigNumber = buyFYToken(
      baseBalance,
      fyTokenBalance,
      fyToken,
      BigNumber.from("110").div(BigNumber.from("100")),
      BigNumber.from("105").div(BigNumber.from("100")),
      timeTillMaturity,
      tsBn,
      g1Bn,
      18, // ???
    );
    const daiWithoutFee: BigNumber = buyFYToken(
      baseBalance,
      fyTokenBalance,
      fyToken,
      BigNumber.from("110").div(BigNumber.from("100")),
      BigNumber.from("105").div(BigNumber.from("100")),
      timeTillMaturity,
      tsBn,
      g1Bn,
      18, // ???
    );
    fee_ = (new Decimal(daiWithFee.toString())).sub(new Decimal(daiWithoutFee.toString()));
  } else {
    const daiWithFee: BigNumber = sellFYToken(baseBalance, fyTokenBalance, fyDai_.mul(BigNumber.from('-1')), timeTillMaturity, scaleFactor);
    const daiWithoutFee: BigNumber = sellFYToken(baseBalance, fyTokenBalance, fyDai_.mul(BigNumber.from('-1')), timeTillMaturity, scaleFactor, true);
    fee_ = (new Decimal(daiWithoutFee.toString())).sub(new Decimal(daiWithFee.toString()));
  }
  return toBn(fee_);
}

export function fyDaiForMint(
  baseBalance: BigNumber | string,
  fyDaiRealBalance: BigNumber | string,
  fyDaiVirtualBalance: BigNumber | string,
  base: BigNumber | string,
  timeTillMaturity: BigNumber | string,
): string {
  const baseBalance_ = new Decimal(baseBalance.toString());
  const fyDaiRealBalance_ = new Decimal(fyDaiRealBalance.toString());
  const timeTillMaturity_ = new Decimal(timeTillMaturity.toString());
  const x = new Decimal(base.toString());
  let min = ZERO;
  let max = x.mul(TWO);
  let yOut = Decimal.floor((min.add(max)).div(TWO));
  let zIn: Decimal

  let i = 0;
  while (true) {
    if (i++ > 100) throw 'Not converging'

    zIn = new Decimal(
      buyFYToken(
        baseBalance,
        fyDaiVirtualBalance,
        BigNumber.from(yOut.toFixed(0)),
        BigNumber.from("110").div(BigNumber.from("100")),
        BigNumber.from("105").div(BigNumber.from("100")),
        timeTillMaturity_.toString(),
        tsBn,
        g1Bn,
        18, // ???
      ).toString(),
    );

    const Z_1 = baseBalance_.add(zIn); // New base balance
    const z_1 = x.sub(zIn) // My remaining base
    const Y_1 = fyDaiRealBalance_.sub(yOut); // New fyToken balance
    const y_1 = yOut // My fyToken
    const pz = z_1.div(z_1.add(y_1)); // base proportion in my assets
    const PZ = Z_1.div(Z_1.add(Y_1)); // base proportion in the balances

    // Targeting between 0.001% and 0.002% slippage (surplus)
    // Lower both if getting "Not enough base in" errors. That means that
    // the calculation that was done off-chain was stale when the actual mint happened.
    // It might be reasonable to set `minTarget` to half the slippage, and `maxTarget`
    // to the slippage. That would also mean that the algorithm would aim to waste at
    // least half the slippage allowed.
    // For large trades, it would make sense to append a `retrieveBase` action at the
    // end of the batch.
    const minTarget = new Decimal(1.00001)
    const maxTarget = new Decimal(1.00002)

    // The base proportion in my assets needs to be higher than but very close to the
    // base proportion in the balances, to make sure all the fyToken is used.
    // eslint-disable-next-line no-plusplus
    if ((PZ.mul(maxTarget) > pz && PZ.mul(minTarget) < pz)) {
      break; // Too many iterations, or found the result
    } else if (PZ.mul(maxTarget) <= pz) {
      min = yOut;
      yOut = (yOut.add(max)).div(TWO); // bought too little fyToken, buy some more
    } else {
      max = yOut;
      yOut = (yOut.add(min)).div(TWO); // bought too much fyToken, buy a bit less
    }
  }

  /* console.log(`
    base reserves: ${baseBalance}
    fyToken virtual reserves: ${fyDaiVirtualBalance}
    fyTokenOut: ${BigNumber.from(yOut.toFixed(0))}
    timeTillMaturity: ${timeTillMaturity_}
    scaleFactor: ${BigNumber.from('1')}
  `)
  const Z_1 = baseBalance_.add(zIn); // New base balance
  const z_1 = x.sub(zIn) // My remaining base
  const Y_1 = fyDaiRealBalance_.sub(yOut); // New fyToken balance
  const y_1 = yOut // My fyToken
  const pz = z_1.div(z_1.add(y_1)); // base proportion in my assets
  const PZ = Z_1.div(Z_1.add(Y_1)); // base proportion in the balances
  console.log(`
    Z_1: ${Z_1.floor().toFixed()}
    Y_1: ${Y_1.floor().toFixed()}
    z_1: ${z_1.floor().toFixed()}
    y_1: ${y_1.floor().toFixed()}
    PZ: ${PZ}
    pz: ${pz}
    i: ${i}
  `) */
  return Decimal.floor(yOut).toFixed();
}

/**
   * Split a certain amount of X liquidity into its two componetnts (eg. base and fyToken)
   * @param { BigNumber } xBalance // eg. base balance
   * @param { BigNumber } yBalance // eg. fyToken balance
   * @param {BigNumber} xAmount // amount to split in wei
   * @returns  [ BigNumber, BigNumber ] returns an array of [base, fyToken]
   */
export const splitLiquidity = (
  xBalance: BigNumber | string,
  yBalance: BigNumber | string,
  xAmount: BigNumber | string,
): [string, string] => {
  const xBalance_ = new Decimal(xBalance.toString());
  const yBalance_ = new Decimal(yBalance.toString());
  const xAmount_ = new Decimal(xAmount.toString());
  const xPortion = (xAmount_.mul(xBalance_)).div(yBalance_.add(xBalance_));
  const yPortion = xAmount_.sub(xPortion);
  return [xPortion.toFixed(), yPortion.toFixed()];
};

/**
   * Calculate Slippage
   * @param { BigNumber } value
   * @param { BigNumber } slippage optional: defaults to 0.005 (0.5%)
   * @param { number } minimise optional: whether the resutl should be a minimum or maximum (default max)
   * @returns { string } human readable string
   */
export const calculateSlippage = (
  value: BigNumber | string,
  slippage: BigNumber | string = '0.005',
  minimise: boolean = false,
): string => {
  const value_ = new Decimal(value.toString());
  const _slippageAmount = floorDecimal(mulDecimal(value, slippage));
  if (minimise) {
    return value_.sub(_slippageAmount).toFixed();
  }
  return value_.add(_slippageAmount).toFixed();
};

/**
   * Calculate Annualised Yield Rate
   * @param { BigNumber | string } rate // current [base] price per unit y[base]
   * @param { BigNumber | string } amount // y[base] amount at maturity
   * @param { number } maturity  // date of maturity
   * @param { number } fromDate // ***optional*** start date - defaults to now()
   * @returns { string | undefined } human readable string
   */
export const calculateAPR = (
  tradeValue: BigNumber | string,
  amount: BigNumber | string,
  maturity: number,
  fromDate: number = (Math.round(new Date().getTime() / 1000)), // if not provided, defaults to current time.
): string | undefined => {
  const tradeValue_ = new Decimal(tradeValue.toString());
  const amount_ = new Decimal(amount.toString());

  if (
    maturity > Math.round(new Date().getTime() / 1000)
  ) {
    const secsToMaturity = maturity - fromDate;
    const propOfYear = new Decimal(secsToMaturity / SECONDS_PER_YEAR);
    const priceRatio = amount_.div(tradeValue_);
    const powRatio = ONE.div(propOfYear);
    const apr = (priceRatio.pow(powRatio)).sub(ONE);

    if (apr.gt(ZERO) && apr.lt(100)) {
      return apr.mul(100).toFixed();
    }
    return undefined;
  }
  return undefined;
};

/**
   * Calculates the collateralization ratio
   * based on the collat amount and value and debt value.
   * @param { BigNumber | string } collateralAmount  amount of collateral ( in wei)
   * @param { BigNumber | string } collateralPrice price of collateral (in USD)
   * @param { BigNumber | string } debtValue value of base debt (in USD)
   * @param {boolean} asPercent OPTIONAL: flag to return ratio as a percentage
   * @returns { string | undefined }
   */
export const collateralizationRatio = (
  collateralAmount: BigNumber | string,
  collateralPrice: BigNumber | string,
  debtValue: BigNumber | string,
  asPercent: boolean = false, // OPTIONAL:  flag to return as percentage
): string | undefined => {
  if (
    ethers.BigNumber.isBigNumber(debtValue) ? debtValue.isZero() : debtValue === '0'
  ) {
    return undefined;
  }
  const _colVal = mulDecimal(collateralAmount, collateralPrice);
  const _ratio = divDecimal(_colVal, debtValue);

  if (asPercent) {
    return mulDecimal('100', _ratio);
  }
  return _ratio;
};

/**
   * Calcualtes the amount (base, or other variant) that can be borrowed based on
   * an amount of collateral (ETH, or other), and collateral price.
   *
   * @param {BigNumber | string} collateralAmount amount of collateral
   * @param {BigNumber | string} collateralPrice price of unit collateral (in currency x)
   * @param {BigNumber | string} debtValue value of debt (in currency x)
   * @param {BigNumber | string} liquidationRatio  OPTIONAL: 1.5 (150%) as default
   *
   * @returns {string}
   */
export const borrowingPower = (
  collateralAmount: BigNumber | string,
  collateralPrice: BigNumber | string,
  debtValue: BigNumber | string,
  liquidationRatio: string = '1.5', // OPTIONAL: 150% as default
): string => {
  const collateralValue = mulDecimal(collateralAmount, collateralPrice);
  const maxSafeDebtValue_ = new Decimal(divDecimal(collateralValue, liquidationRatio));
  const debtValue_ = new Decimal(debtValue.toString());
  const _max = debtValue_.lt(maxSafeDebtValue_) ? maxSafeDebtValue_.sub(debtValue_) : new Decimal('0');
  return _max.toFixed(0);
};
