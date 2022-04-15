// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

/* POOL ERRORS
******************************************************************************************************************/

/// An invalid maturity date was passed into the constructor. Maturity date must be less than type(uint64).max
error MaturityOverflow();

/// The pool has matured.  Trades are not allowed after maturity.
error AfterMaturity();

/// The reserves have changed compared with the last cache which causes the trade to fall below or above the min/max
/// slippage ratio selected.  This is likely a result of a sandwich attack.
error Slippage();

/// Mu is the initial c reading, usually obtained through an external call to the base contract. It cannot be zero.
error MuZero();
