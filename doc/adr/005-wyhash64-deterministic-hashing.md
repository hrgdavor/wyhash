# 005: Wyhash64 for deterministic hashing

> **Copied here from the Dia-Log project's ADR 005 on 2026-10-16, when the implementation moved into this
> project.** The decision text below is as it was written there, with two deliberate changes: its
> dia-log-relative links became code spans (they would be dead here, and the amendment has the live links), and
> the "Zig 0.15" reference stayed as it was, because it records when the decision was made. **The amendment at
> the end is what applies to this project.** Dia-log's own record of the extraction is its ADR 014.

* **Status:** Accepted
* **Date:** 2026-07-26
* **Implementation Status:** Implemented — now in this project; see the amendment

## Context

The project requires a fast, deterministic hash function for:
- Fingerprinting stack traces for deduplication in log aggregation systems (Elasticsearch, Loki)
- Generating unique identifiers for error grouping

Requirements for the hash function:
- **Deterministic**: Same input must always produce the same output, even across different JVM versions and builds
- **Fast**: Must not add significant overhead to log event processing
- **Good distribution**: Minimize collisions for similar but distinct stack traces
- **No external dependencies**: Should not require additional libraries beyond the JDK

Java's built-in `hashCode()` is not suitable because:
- It is not guaranteed to be consistent across JVM implementations
- It has poor distribution for certain input patterns
- It is not designed for cryptographic or deduplication purposes

## Options Considered

1. **Java built-in hashCode():** No external dependency, but not deterministic across JVM versions and has poor distribution.
2. **MurmurHash3:** Fast and well-distributed, but requires external library or custom implementation.
3. **Wyhash64:** Fast, deterministic, good distribution, and can be implemented as a standalone Java class with no external dependencies.

## Decision

Implement a standalone port of Wyhash64, a fast non-cryptographic hash function originally written in Zig. The implementation — then `hr.hrg.dialog.core.Wyhash64` in dia-log's `core` module, now the file this project is built from — includes:

- **Single-shot hashing**: `Wyhash64.hash(seed, byte[])` and `Wyhash64.hash(seed, ByteBuffer)` for fixed-size inputs
- **Streaming hashing**: `Wyhash64.Streaming` class for incrementally hashing variable-length inputs (used for stack trace fingerprinting)
- **Little-endian reads**: Uses `VarHandle` with `ByteOrder.LITTLE_ENDIAN` for efficient byte-to-long conversion
- **Default secret constants**: Matches Zig 0.15 `std.hash.Wyhash` constants for cross-language compatibility

The hash is used in dia-log's `JsonLogWriter.writeJsonEvent()` (its `logback` module) to produce a 16-character hex value written as `"errHash"` (a top-level JSON field) for each exception. The fingerprint itself comes from `JavaStackSanitizer.fingerprint()`.

## Consequences

* **Positive:** Very fast: Wyhash64 is designed for high throughput with minimal CPU instructions; deterministic across platforms: Same algorithm, same constants, same output; streaming support enables efficient hashing of long stack traces without buffering the entire trace; no external dependencies: Pure Java implementation using only `java.lang.invoke` and `java.nio`; cross-language compatibility: Matches Zig's Wyhash, enabling consistent hashing across polyglot systems.
* **Negative:** Not cryptographically secure (not needed for this use case, but worth documenting); the `Streaming` class has a 48-byte internal buffer, adding slight memory overhead; `VarHandle` usage requires Java 9+ (project already requires Java 21).

## References

- `hr.hrg.dialog.core.Wyhash64` — the class's home until 2026-10-16 (see the amendment)
- `JavaStackSanitizer.fingerprint()` in dia-log's `core` — the caller that needs the streaming form
- [Zig std.hash.Wyhash](https://github.com/ziglang/zig/blob/master/lib/std/hash/wyhash.zig)

## Amendment (2026-10-16) — the implementation's home

The decision above stands. What changed is **where the implementation lives and who maintains it**, and the
reasons are the same ones that made a standalone class attractive in the first place.

**The implementation moved into this project.** The class that grew out of this ADR —
`hr.hrg.dialog.core.Wyhash64`, the one with the zero-allocation `String` paths, the `char[]`/`CharSequence`
handling and the streaming form — now lives here as
[`hr.hrg.wyhash.Wyhash64`](../../src/main/java/hr/hrg/wyhash/Wyhash64.java). Only its package changed; its nine
test classes and its design document ([`doc/zero-allocation.md`](../../doc/zero-allocation.md)) came with it.

**This project is now `hr.hrg:wyhash`, and it supersedes the published `1.0.0`.** The coordinates are the ones
`java-watch-core`, `jcodebuddy-agent` and the projects that consume it already resolve; the Java port moved here so that there
is one implementation rather than a published artifact plus copies of it (a second copy is still vendored inside
`jcodebuddy-core`). Version `1.1.0` (developed as `1.1.0-SNAPSHOT`): the same algorithm and — this is the part the ADR's determinism
requirement makes non-negotiable — **the same values**, every one of them pinned by
[`conformance/wyhash-vectors.json`](../../conformance/wyhash-vectors.json), which is generated from the
reference rather than from any port.

**The reference is the Zig builtin, `std.hash.Wyhash`** — the line above says "Zig 0.15" because that was the
release in front of the author in July 2026. The project treats the builtin as the definition and records the
release it generated its vectors under (0.17 at the time of writing); regenerating them under 0.17 produced a
file identical to the 0.16 one apart from that recorded version, so "matches Zig's Wyhash" is a property that
has held across the upgrade rather than a one-time observation.

**What arrived with the move, and what was added.** All three of the original API surfaces are here, and the
`Streaming` class the ADR required for stack-trace fingerprinting is the one `ChecksumDatabase` in the watcher
family streams binary files through. Added on top: `Wyhash64.hex(long)` — the 16-lowercase-character form
`errHash` and every other table in the family writes, so no caller invents its own formatting — and a
`MemorySegment` path for callers that already hold bytes off-heap (a memory-mapped file, an arena allocation),
which is not a replacement for the `char[]` handling: that stays allocation-free by packing chars itself.

**The "no external dependencies" requirement is still met, in the stronger sense.** `hr.hrg:wyhash` has **no
runtime dependency at all**: the Java port is `java.lang.invoke`, `java.nio` and `java.lang.foreign`. A consumer
of the old published artifact had the same property; a consumer of this project gets the same class plus its
tests, its vectors and its other ports (JavaScript and Zig), which is what makes "same algorithm, same
constants, same output" checkable instead of asserted.

**For Dia-Log specifically:** its next release declares `hr.hrg:wyhash` and deletes `core`'s copy — an import
change at every use site (`hr.hrg.dialog.core.Wyhash64` → `hr.hrg.wyhash.Wyhash64`) and nothing else, because the
values do not move. That decision is recorded in dia-log's own ADR 014.