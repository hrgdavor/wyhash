// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Davor Hrg
//
// The Zig port of wyhash64 — and, because this project's definition IS `std.hash.Wyhash`, the reference variant
// in its own language. There is deliberately no transcription of the algorithm here: a second copy of the
// reference would be a second thing to keep equal to the reference, and the vectors exist to keep the *other*
// ports equal to it (WYHASH.md § 2).
//
// The conformance tests are `../tests.zig`, the project's Zig entry point:
//
//     zig test tests.zig                      (from this project's directory)
//
// They live one level up because a Zig test file may only `@embedFile` inside its own package path, and the
// shared vectors belong to `conformance/`, not to a port.

const std = @import("std");

/// The seed the consuming projects' tables use. A caller may pass another one — the vectors' `seedCases` pin
/// that a non-zero seed is honoured rather than ignored.
pub const SEED: u64 = 0;

/// The builtin's incremental form, exposed under this project's name so a caller does not have to know which
/// builder was chosen. `init(seed)` / `update(bytes)` / `final()` must equal `hash(seed, all bytes at once)`,
/// which the `pattern-1048576` case pins for a large input.
pub const Streaming = std.hash.Wyhash;

/// The 64-bit hash of `bytes` under `seed`. This is the definition the other ports are held to.
pub fn hash(seed: u64, bytes: []const u8) u64 {
    return std.hash.Wyhash.hash(seed, bytes);
}

/// `byte[i] = (i * 7 + 3) & 0xFF` — the bytes a `pattern` case describes (WYHASH.md § 4).
pub fn fillPattern(bytes: []u8) void {
    for (bytes, 0..) |*byte, index| {
        byte.* = @intCast((index * 7 + 3) & 0xFF);
    }
}