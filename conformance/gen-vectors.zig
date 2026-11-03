// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Davor Hrg
//! Generates `wyhash-vectors.json` from THE REFERENCE: `std.hash.Wyhash`, the Zig builtin.
//!
//! Run it from this directory and capture stdout:
//!
//!     zig run gen-vectors.zig > wyhash-vectors.json
//!
//! WHY THE REFERENCE IS THIS PROGRAM'S `std.hash.Wyhash`, AND NOT A PORT. The variant this project treats as
//! the definition is the Zig builtin's, because that is the variant the Java implementations in circulation
//! already follow: `hr.hrg.wyhash:wyhash:1.0.0` reproduces `std.hash.Wyhash` value for value, and so does the
//! vendored copy in `jcodebuddy-core`. Generating the vectors from the builtin therefore pins every other port
//! to the same definition the existing Java code was written against, rather than to whichever port happened
//! to be written first.
//!
//! The text cases are the *library-produced* vectors (the ones `ContentHashTest` in `hipster-entity-tooling`
//! pins its vendored copy to, produced by `hr.hrg.wyhash:wyhash:1.0.0`, not by a copy of it). The builtin
//! agrees with every one of them — that agreement is the whole premise of this file — so the committed vector
//! set is anchored twice: to the library the Java side uses today, and to the builtin the Java side will be
//! merged onto.
//!
//! `pattern` cases exist because a hash's branches are chosen by length, and a table of text fixtures alone
//! would leave the multi-block and tail paths pinned only up to the longest string someone happened to write.
//! Their bytes are defined by `WYHASH.md` § 4 (`byte[i] = (i * 7 + 3) & 0xFF`), which is three lines in any
//! language.

const std = @import("std");
const builtin = @import("builtin");

const CaseKind = enum { text, pattern };

const TextCase = struct {
    label: []const u8,
    text: []const u8,
};

const PatternCase = struct {
    label: []const u8,
    length: usize,
};

/// The text fixtures, the library-produced goldens first.
const TEXT_CASES = [_]TextCase{
    .{ .label = "empty", .text = "" },
    .{ .label = "one-byte", .text = "x" },
    .{ .label = "a", .text = "a" },
    .{ .label = "lf (12 bytes)", .text = "line1\nline2\n" },
    .{ .label = "crlf (14 bytes, raw)", .text = "line1\r\nline2\r\n" },
    .{ .label = "utf8 (7 bytes)", .text = "h\u{e9}llo\n" },
    .{ .label = "exactly 16 bytes", .text = "0123456789abcdef" },
    .{ .label = "17 bytes", .text = "0123456789abcdefg" },
    .{ .label = "exactly 48 bytes", .text = "0123456789abcdef0123456789abcdef0123456789abcdef" },
    .{ .label = "49 bytes", .text = "0123456789abcdef0123456789abcdef0123456789abcdef0" },
    .{ .label = "name a.txt", .text = "a.txt" },
    .{ .label = "name src/b.java", .text = "src/b.java" },
    .{ .label = "name README.md", .text = "README.md" },
    .{ .label = "name z/y/z.txt", .text = "z/y/z.txt" },
};

/// 900 repetitions of `0123456789ab`: the library's own multi-block vector, 10 800 bytes.
///
/// Built at run time rather than with the old `**` repetition operator, which Zig 0.17 removed — so this file
/// compiles under both 0.16 and 0.17 without a version switch.
const REPEATED_UNIT = "0123456789ab";
const REPEATED_COUNT: usize = 900;
const REPEATED_LABEL = "900 x 0123456789ab (library vector)";

fn repeatedText(allocator: std.mem.Allocator) ![]u8 {
    const out = try allocator.alloc(u8, REPEATED_UNIT.len * REPEATED_COUNT);
    for (0..REPEATED_COUNT) |index| {
        @memcpy(out[index * REPEATED_UNIT.len ..][0..REPEATED_UNIT.len], REPEATED_UNIT);
    }
    return out;
}

/// The lengths that walk the algorithm's branches: the `<= 16` short path, `17`, the 48-byte block loop, its
/// boundary `49`, the 16-byte tail loop at `64`/`100`, and a one-mebibyte input so a streaming implementation
/// has something to disagree with.
const PATTERN_CASES = [_]PatternCase{
    .{ .label = "pattern-4", .length = 4 },
    .{ .label = "pattern-7", .length = 7 },
    .{ .label = "pattern-8", .length = 8 },
    .{ .label = "pattern-15", .length = 15 },
    .{ .label = "pattern-16", .length = 16 },
    .{ .label = "pattern-17", .length = 17 },
    .{ .label = "pattern-31", .length = 31 },
    .{ .label = "pattern-32", .length = 32 },
    .{ .label = "pattern-47", .length = 47 },
    .{ .label = "pattern-48", .length = 48 },
    .{ .label = "pattern-49", .length = 49 },
    .{ .label = "pattern-64", .length = 64 },
    .{ .label = "pattern-100", .length = 100 },
    .{ .label = "pattern-255", .length = 255 },
    .{ .label = "pattern-256", .length = 256 },
    .{ .label = "pattern-1000", .length = 1000 },
    .{ .label = "pattern-10800", .length = 10_800 },
    .{ .label = "pattern-1048576", .length = 1_048_576 },
};

/// `byte[i] = (i * 7 + 3) & 0xFF`, the one pattern this project's cases use.
fn fillPattern(bytes: []u8) void {
    for (bytes, 0..) |*byte, index| {
        byte.* = @intCast((index * 7 + 3) & 0xFF);
    }
}

/// The seeded cases. Every other case in this file is seed 0 — the seed `fs-meta` and the existing Java tables
/// use — and a port that quietly ignored its seed parameter would pass all of them. These are the inputs that
/// stop that, including both extremes of the range. The seed is written as sixteen hex characters, because
/// `0x9E3779B97F4A7C15` does not survive a JSON number's double precision.
const SeedCase = struct {
    label: []const u8,
    seed: u64,
    text: []const u8,
};

const SEED_CASES = [_]SeedCase{
    .{ .label = "empty, seed 1", .seed = 1, .text = "" },
    .{ .label = "a, seed 1", .seed = 1, .text = "a" },
    .{ .label = "lf (12 bytes), seed 1", .seed = 1, .text = "line1\nline2\n" },
    .{ .label = "17 bytes, seed 0x9E3779B97F4A7C15", .seed = 0x9E3779B97F4A7C15, .text = "0123456789abcdefg" },
    .{
        .label = "49 bytes, seed 0x9E3779B97F4A7C15",
        .seed = 0x9E3779B97F4A7C15,
        .text = "0123456789abcdef0123456789abcdef0123456789abcdef0",
    },
    .{ .label = "empty, seed 0xFFFFFFFFFFFFFFFF", .seed = 0xFFFFFFFFFFFFFFFF, .text = "" },
    .{ .label = "a, seed 0xFFFFFFFFFFFFFFFF", .seed = 0xFFFFFFFFFFFFFFFF, .text = "a" },
};

/// **The reference's own acceptance vectors**: the `test` block of Zig's `lib/std/hash/wyhash.zig`, reproduced
/// here by *calling the builtin* rather than transcribing its expected values — so this file cannot disagree with
/// the reference about them, and a port that asserts this file is held to the same set the reference holds itself
/// to. These were the only vectors the project had before the generator existed (they were a hand-written JUnit
/// test in `WyhashTestVectors`), and they are worth keeping in the generated contract for that reason: a library
/// consumer can check a port against the reference's own numbers.
///
/// Two of them (`seed 0, ""` and `seed 1, "a"`) also appear as a library golden and as a seed case above. That is
/// deliberate rather than an oversight: the labels name the different provenance, and the file is generated, so
/// the redundancy costs a line and says "both sources agree" where it appears.
const BUILTIN_CASES = [_]SeedCase{
    .{ .label = "zig builtin vector: seed 0, \"\"", .seed = 0, .text = "" },
    .{ .label = "zig builtin vector: seed 1, \"a\"", .seed = 1, .text = "a" },
    .{ .label = "zig builtin vector: seed 2, \"abc\"", .seed = 2, .text = "abc" },
    .{ .label = "zig builtin vector: seed 3, \"message digest\"", .seed = 3, .text = "message digest" },
    .{
        .label = "zig builtin vector: seed 4, \"abcdefghijklmnopqrstuvwxyz\"",
        .seed = 4,
        .text = "abcdefghijklmnopqrstuvwxyz",
    },
    .{
        .label = "zig builtin vector: seed 5, A-Za-z0-9",
        .seed = 5,
        .text = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789",
    },
    .{
        .label = "zig builtin vector: seed 6, 80 digits",
        .seed = 6,
        .text = "12345678901234567890123456789012345678901234567890123456789012345678901234567890",
    },
};

fn hash(bytes: []const u8) u64 {
    return std.hash.Wyhash.hash(0, bytes);
}

fn writeJsonString(writer: *std.Io.Writer, text: []const u8) !void {
    try writer.writeByte('"');
    for (text) |byte| {
        switch (byte) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => {
                if (byte < 0x20) {
                    try writer.print("\\u{x:0>4}", .{byte});
                } else {
                    try writer.writeByte(byte);
                }
            },
        }
    }
    try writer.writeByte('"');
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, gpa);
    defer args.deinit();
    _ = args.next();                                  // the program itself
    const mode = args.next() orelse "json";

    var out_buffer: [1 << 16]u8 = undefined;
    var file_writer = std.Io.File.stdout().writer(init.io, &out_buffer);
    const writer = &file_writer.interface;

    if (std.mem.eql(u8, mode, "json")) {
        try emitJson(writer, std.heap.page_allocator);
    } else if (std.mem.eql(u8, mode, "java")) {
        try emitJava(writer, std.heap.page_allocator);
    } else {
        std.debug.print("usage: gen-vectors.zig [json|java]\n", .{});
        std.process.exit(2);
    }
    try writer.flush();
}

/// The canonical artefact: the vector file every port parses.
fn emitJson(writer: *std.Io.Writer, gpa: std.mem.Allocator) !void {
    try writer.writeAll("{\n");
    try writer.writeAll("  \"format\": \"wyhash-vectors\",\n");
    try writer.writeAll("  \"version\": 1,\n");
    try writer.writeAll("  \"reference\": {\n");
    try writer.writeAll("    \"variant\": \"zig-builtin\",\n");
    try writer.writeAll("    \"builder\": \"std.hash.Wyhash\",\n");
    try writer.writeAll("    \"seed\": 0,\n");
    try writer.print("    \"zigVersion\": \"{s}\"\n", .{builtin.zig_version_string});
    try writer.writeAll("  },\n");
    try writer.writeAll("  \"note\": \"Generated by conformance/gen-vectors.zig from std.hash.Wyhash - see that file and WYHASH.md. Do not hand-edit.\",\n");
    try writer.writeAll("  \"cases\": [\n");

    var first = true;
    for (TEXT_CASES) |case| {
        if (!first) try writer.writeAll(",\n");
        first = false;
        try writer.writeAll("    { \"label\": ");
        try writeJsonString(writer, case.label);
        try writer.writeAll(", \"text\": ");
        try writeJsonString(writer, case.text);
        try writer.print(", \"wyhash64\": \"{x:0>16}\" }}", .{hash(case.text)});
    }
    // The library's own 10 800-byte vector, and the one text case that is not a hand-written fixture.
    if (!first) try writer.writeAll(",\n");
    const repeated = try repeatedText(gpa);
    defer gpa.free(repeated);
    try writer.writeAll("    { \"label\": \"");
    try writer.writeAll(REPEATED_LABEL);
    try writer.writeAll("\", \"text\": ");
    try writeJsonString(writer, repeated);
    try writer.print(", \"wyhash64\": \"{x:0>16}\" }}", .{hash(repeated)});

    for (PATTERN_CASES) |case| {
        try writer.writeAll(",\n");
        const bytes = try gpa.alloc(u8, case.length);
        defer gpa.free(bytes);
        fillPattern(bytes);
        try writer.writeAll("    { \"label\": ");
        try writeJsonString(writer, case.label);
        try writer.writeAll(", \"pattern\": { \"kind\": \"index7plus3\", \"length\": ");
        try writer.print("{d}", .{case.length});
        try writer.writeAll(" }, \"wyhash64\": ");
        try writer.print("\"{x:0>16}\" }}", .{hash(bytes)});
    }

    try writer.writeAll("\n  ],\n  \"seedCases\": [\n");
    for (SEED_CASES, 0..) |case, index| {
        if (index > 0) try writer.writeAll(",\n");
        try writer.writeAll("    { \"label\": ");
        try writeJsonString(writer, case.label);
        try writer.writeAll(", \"text\": ");
        try writeJsonString(writer, case.text);
        try writer.print(", \"seed\": \"{x:0>16}\", \"wyhash64\": \"{x:0>16}\" }}", .{
            case.seed,
            std.hash.Wyhash.hash(case.seed, case.text),
        });
    }
    // The reference's own acceptance vectors, in the same array because they are the same shape of case.
    for (BUILTIN_CASES) |case| {
        try writer.writeAll(",\n");
        try writer.writeAll("    { \"label\": ");
        try writeJsonString(writer, case.label);
        try writer.writeAll(", \"text\": ");
        try writeJsonString(writer, case.text);
        try writer.print(", \"seed\": \"{x:0>16}\", \"wyhash64\": \"{x:0>16}\" }}", .{
            case.seed,
            std.hash.Wyhash.hash(case.seed, case.text),
        });
    }

    try writer.writeAll("\n  ]\n}\n");
}

/// The same cases as a Java source file, for the port that has no JSON reader and no dependency to borrow one
/// from: `Wyhash64` is pure JDK, and its tests stay that way. Text fixtures are emitted as **hex**, which is
/// what they are — a `text` case in the JSON is the UTF-8 byte sequence, and hex says so without an escaping
/// rule that could disagree with the JSON.
///
///     zig run conformance/gen-vectors.zig -- java > src/test/java/hr/hrg/wyhash/WyhashVectors.java
///
/// `check-ports.mjs` diffs this output against the committed file, the same way it diffs the JSON, so the two
/// artefacts cannot describe different vectors.
fn emitJava(writer: *std.Io.Writer, gpa: std.mem.Allocator) !void {
    try writer.writeAll(
        \\// SPDX-License-Identifier: MIT
        \\// Copyright (c) 2026 Davor Hrg
        \\//
        \\// GENERATED by conformance/gen-vectors.zig from std.hash.Wyhash (the reference).
        \\// Do not hand-edit: run the generator and commit its output.
        \\//
        \\// A case's bytes are `hex` when it has one (the JSON's `text` cases, as their UTF-8 byte sequence) or
        \\// `patternLength >= 0` (`byte[i] = (i * 7 + 3) & 0xFF`). `seed` is the seed that case was generated
        \\// with; the vectors' other cases are seed 0.
        \\package hr.hrg.wyhash;
        \\
        \\import java.util.HexFormat;
        \\
        \\/** The reference's own vector table: see conformance/wyhash-vectors.json and WYHASH.md. */
        \\final class WyhashVectors {
        \\
        \\    private WyhashVectors() {
        \\    }
        \\
        \\    /** One case: bytes by hex-or-pattern, a seed, and the value the reference produced. */
        \\    record Vector(String label, String hex, int patternLength, long seed, String expected) {
        \\
        \\        boolean isPattern() {
        \\            return patternLength >= 0;
        \\        }
        \\
        \\        byte[] bytes() {
        \\            if (isPattern()) {
        \\                byte[] bytes = new byte[patternLength];
        \\                for (int i = 0; i < patternLength; i++) {
        \\                    bytes[i] = (byte) ((i * 7 + 3) & 0xFF);
        \\                }
        \\                return bytes;
        \\            }
        \\            return HexFormat.of().parseHex(hex);
        \\        }
        \\    }
        \\
        \\    static final Vector[] CASES = {
        \\
    );

    var first = true;
    for (TEXT_CASES) |case| {
        if (!first) try writer.writeAll(",\n");
        first = false;
        try writer.writeAll("        new Vector(");
        try writeJavaString(writer, case.label);
        try writer.writeAll(", ");
        try writeHexString(writer, case.text);
        try writer.print(", -1, 0L, \"{x:0>16}\")", .{hash(case.text)});
    }
    if (!first) try writer.writeAll(",\n");
    const repeated = try repeatedText(gpa);
    defer gpa.free(repeated);
    try writer.writeAll("        new Vector(\"");
    try writer.writeAll(REPEATED_LABEL);
    try writer.writeAll("\", ");
    try writeHexString(writer, repeated);
    try writer.print(", -1, 0L, \"{x:0>16}\")", .{hash(repeated)});

    for (PATTERN_CASES) |case| {
        try writer.writeAll(",\n");
        const bytes = try gpa.alloc(u8, case.length);
        defer gpa.free(bytes);
        fillPattern(bytes);
        try writer.writeAll("        new Vector(");
        try writeJavaString(writer, case.label);
        try writer.print(", null, {d}, 0L, \"{x:0>16}\")", .{ case.length, hash(bytes) });
    }

    for (SEED_CASES) |case| {
        try writer.writeAll(",\n");
        try writer.writeAll("        new Vector(");
        try writeJavaString(writer, case.label);
        try writer.writeAll(", ");
        try writeHexString(writer, case.text);
        try writer.print(", -1, 0x{x:0>16}L, \"{x:0>16}\")", .{
            case.seed,
            std.hash.Wyhash.hash(case.seed, case.text),
        });
    }

    for (BUILTIN_CASES) |case| {
        try writer.writeAll(",\n");
        try writer.writeAll("        new Vector(");
        try writeJavaString(writer, case.label);
        try writer.writeAll(", ");
        try writeHexString(writer, case.text);
        try writer.print(", -1, 0x{x:0>16}L, \"{x:0>16}\")", .{
            case.seed,
            std.hash.Wyhash.hash(case.seed, case.text),
        });
    }

    try writer.writeAll(
        \\
        \\    };
        \\}
        \\
    );
}

/// A Java string literal: `"` and `\` escaped, and every non-ASCII byte as a `\u` escape, so the generated
/// file is pure ASCII and no source-encoding question can change a label.
fn writeJavaString(writer: *std.Io.Writer, text: []const u8) !void {
    try writer.writeByte('"');
    for (text) |byte| {
        switch (byte) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            else => {
                if (byte < 0x20 or byte >= 0x7f) {
                    try writer.print("\\u{x:0>4}", .{byte});
                } else {
                    try writer.writeByte(byte);
                }
            },
        }
    }
    try writer.writeByte('"');
}

/// The bytes of a text fixture as a Java string of hex digits.
fn writeHexString(writer: *std.Io.Writer, bytes: []const u8) !void {
    const digits = "0123456789abcdef";
    try writer.writeByte('"');
    for (bytes) |byte| {
        try writer.writeByte(digits[byte >> 4]);
        try writer.writeByte(digits[byte & 0x0f]);
    }
    try writer.writeByte('"');
}