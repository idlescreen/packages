// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 IdleScreen

//! Deterministic PRNG for test case generation.

#![allow(dead_code)]

/// xorshift64* — small deterministic PRNG, adequate for test case generation.
pub struct Rng(pub(crate) u64);

impl Rng {
    pub fn new(seed: u64) -> Self {
        Self(seed | 1)
    }

    pub fn next(&mut self) -> u64 {
        let mut x = self.0;
        x ^= x >> 12;
        x ^= x << 25;
        x ^= x >> 27;
        self.0 = x;
        x.wrapping_mul(0x2545_F491_4F6C_DD1D)
    }

    /// Uniform value in `0..n` (n must be > 0).
    pub fn below(&mut self, n: u64) -> u64 {
        self.next() % n
    }

    /// Uniform value in `lo..=hi` inclusive.
    pub fn range(&mut self, lo: u64, hi: u64) -> u64 {
        lo + self.below(hi - lo + 1)
    }

    pub fn boolean(&mut self) -> bool {
        self.next() & 1 == 1
    }

    /// `Some(inner)` ~80% of the time, else `None` — like `prop::option::of`.
    pub fn opt<T>(&mut self, f: impl FnOnce(&mut Self) -> T) -> Option<T> {
        if self.below(5) == 0 {
            None
        } else {
            Some(f(self))
        }
    }

    /// Random length in `min..=max`, then that many picks from `chars`.
    pub fn string(&mut self, chars: &[char], min: usize, max: usize) -> String {
        let len = self.range(min as u64, max as u64) as usize;
        (0..len)
            .map(|_| chars[self.below(chars.len() as u64) as usize])
            .collect()
    }
}
