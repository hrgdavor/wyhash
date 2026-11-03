// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Davor Hrg
//
// The Zig port's conformance tests, and the project's Zig entry point:
//
//     zig test tests.zig                       (from the wyhash/ directory)
//
// It sits at the project root rather than inside `zig/` for one reason: a Zig test file may only `@embedFile`
// paths inside its own package path, and the vectors belong to `conformance/` — shared by every port — rather
// than to this one. The port itself is `zig/wyhash.zig`.
//
// The vectors are embedded, not read at run time, so these tests cannot pass against a file other than the
// committed one, and the reference metadata is asserted as well as the values: if `std.hash.Wyhash` ever stops
// being the variant the file names, that is a failure rather than a silent redefinition of the project.

const std = @import("std");
const wyhash = @import("zig/wyhash.zig");

const Pattern = struct {
    kind: []const u8,
    length: usize,
};

const Case = struct {
    label: []const u8,
    text: ?[]const u8 = null,
    pattern: ?Pattern = null,
    wyhash64: []const u8,
};

const SeedCase = struct {
    label: []const u8,
    text: []const u8,
    seed: []const u8,
    wyhash64: []const u8,
};

const Reference = struct {
    variant: []const u8,
    builder: []const u8,
    seed: u64,
    zigVersion: []const u8,
};

const Vectors = struct {
    reference: Reference,
    cases: []const Case,
    seedCases: []const SeedCase,
};

const vectors_json = @embedFile("conformance/wyhash-vectors.json");

fn hex(allocator: std.mem.Allocator, value: u64) ![]u8 {
    return std.fmt.allocPrint(allocator, "{x:0>16}", .{value});
}

test "the builtin this port wraps is the reference the vectors name" {
    const allocator = std.testing.allocator;
    var parsed = try std.json.parseFromSlice(Vectors, allocator, vectors_json, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();

    try std.testing.expectEqualStrings("zig-builtin", parsed.value.reference.variant);
    try std.testing.expectEqualStrings("std.hash.Wyhash", parsed.value.reference.builder);
    try std.testing.expectEqual(wyhash.SEED, parsed.value.reference.seed);
    // Provenance, not a check: another Zig version may build this project, and if the builtin changed under
    // it, the cases below are what fails.
    try std.testing.expect(parsed.value.reference.zigVersion.len > 0);
}

test "every case in the reference vector file" {
    const allocator = std.testing.allocator;
    var parsed = try std.json.parseFromSlice(Vectors, allocator, vectors_json, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();

    var checked: usize = 0;
    for (parsed.value.cases) |case| {
        const actual = if (case.pattern) |pattern| blk: {
            try std.testing.expectEqualStrings("index7plus3", pattern.kind);
            const bytes = try allocator.alloc(u8, pattern.length);
            defer allocator.free(bytes);
            wyhash.fillPattern(bytes);
            break :blk wyhash.hash(wyhash.SEED, bytes);
        } else wyhash.hash(wyhash.SEED, case.text.?);

        const actual_hex = try hex(allocator, actual);
        defer allocator.free(actual_hex);
        std.testing.expectEqualStrings(case.wyhash64, actual_hex) catch |failure| {
            std.debug.print("case '{s}': got {s}, vectors say {s}\n", .{ case.label, actual_hex, case.wyhash64 });
            return failure;
        };
        checked += 1;
    }
    // 33 as generated: the text fixtures, the library's 10 800-byte vector, and the lengths that walk the
    // algorithm's branches. A vector file that lost most of its cases is a failure too.
    try std.testing.expect(checked >= 30);
}

test "the seeded cases, so a port cannot ignore its seed" {
    const allocator = std.testing.allocator;
    var parsed = try std.json.parseFromSlice(Vectors, allocator, vectors_json, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();

    for (parsed.value.seedCases) |case| {
        const seed = try std.fmt.parseInt(u64, case.seed, 16);
        const actual_hex = try hex(allocator, wyhash.hash(seed, case.text));
        defer allocator.free(actual_hex);
        std.testing.expectEqualStrings(case.wyhash64, actual_hex) catch |failure| {
            std.debug.print("case '{s}': got {s}, vectors say {s}\n", .{ case.label, actual_hex, case.wyhash64 });
            return failure;
        };
    }
}

test "the streaming form equals the one-shot form on a large input" {
    const allocator = std.testing.allocator;
    const bytes = try allocator.alloc(u8, 1_048_576);
    defer allocator.free(bytes);
    wyhash.fillPattern(bytes);

    var streaming = wyhash.Streaming.init(wyhash.SEED);
    streaming.update(bytes[0 .. bytes.len / 3]);
    streaming.update(bytes[bytes.len / 3 ..]);
    try std.testing.expectEqual(wyhash.hash(wyhash.SEED, bytes), streaming.final());
}