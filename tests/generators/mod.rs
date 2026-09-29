//! Deterministic std-only generators replacing `proptest` strategies.
//!
//! Each test seeds its own `Rng` and loops a fixed case count, so runs are
//! reproducible without any external property-testing crate.
// SPDX-License-Identifier: Apache-2.0
#![allow(dead_code)]

pub mod rng;
pub mod values;

pub use rng::*;
pub use values::*;
