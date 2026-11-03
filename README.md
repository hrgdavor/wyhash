# wyhash

One 64-bit non-cryptographic hash — the variant the **Zig** standard library implements (`std.hash.Wyhash`) —
with one Java implementation and, in the same repository, the JavaScript and Zig ports that are held to the same
generated vectors. The Java artifact is `hr.hrg:wyhash`.

> [!IMPORTANT]
> This implementation is intended for **file change tracking** and general-purpose non-cryptographic hashing. It
> is **not** meant for security-sensitive cryptographic applications.

## What is in this repository

| In this repository                                                                               | What it is                                                                                  |
| ------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------- |
| `pom.xml`, `src/main/java/hr/hrg/wyhash/Wyhash64.java`                                           | the **Java port** — `hr.hrg:wyhash`, no runtime dependency beyond the JDK                   |
| `src/test/java/hr/hrg/wyhash/`                                                                   | its tests (144): the algorithm's branches, offsets, streaming, the zero-allocation `String` paths, `MemorySegment`, and the vector tables |
| [`WYHASH.md`](WYHASH.md)                                                                         | the definition: the reference, what a port must expose, and what the vectors pin            |
| [`doc/zero-allocation.md`](doc/zero-allocation.md)                                               | the design of every Java path that copies nothing — the VarHandle `String` paths, char packing, the reusable streaming buffer |
| [`doc/adr/005-wyhash64-deterministic-hashing.md`](doc/adr/005-wyhash64-deterministic-hashing.md) | why this hash was chosen, and how the implementation came to live here (amended 2026-10-16) |
| `js/wyhash64.mjs` + `js/wyhash64.test.mjs`                                                       | the **JavaScript port** — BigInt arithmetic, no dependencies                                |
| `zig/wyhash.zig` + `tests.zig`                                                                   | the **Zig port** — a thin wrapper over the reference itself, so it cannot drift from it     |
| `conformance/gen-vectors.zig` + `conformance/wyhash-vectors.json`                                | the **generated vectors**, produced from the reference (`std.hash.Wyhash`) rather than from any port |
| `src/test/java/hr/hrg/wyhash/WyhashVectors.java`                                                 | the same cases as generated Java source, for the port that has no JSON reader and takes no dependency to borrow one |
| [`check-ports.mjs`](check-ports.mjs)                                                             | one command that proves all of the above are still true                                     |

## Running the checks

```sh
bun check-ports.mjs    # reference integrity (both generated artefacts), the JS port, the Java port, the Zig port
bun test js            # the JavaScript port's tests (6)
mvn package            # the Java port's tests (144; surefire opens java.lang for the zero-allocation paths)
zig test tests.zig     # the Zig port's tests (from this directory, Zig 0.17+)
```

`check-ports.mjs` resolves its own toolchains and **verifies their versions** rather than trusting `PATH`: Zig
0.17+ (the sources are written for it) and a JDK 22+ (`java.lang.foreign`, for the `MemorySegment` input).
Overrides: `WYHASH_ZIG`, `WYHASH_JDK` (or `JAVA_HOME`), and `ZIG`, which Zig's own tooling reads. It checks four
separate claims, because they fail for different reasons:

1. **Reference integrity** — it re-runs `conformance/gen-vectors.zig` and compares the output with *both*
   committed artefacts. If a Zig upgrade ever changes `std.hash.Wyhash`, this fails **before** any port can
   "pass" against yesterday's algorithm.
2. **The JavaScript port** — every case and every seeded case, with the library-produced golden vectors asserted
   first.
3. **The Java port** — compiled with plain `javac`/`java` (no Maven, no JUnit) and run: every case through
   `byte[]`, through `MemorySegment`, and through the streaming form.
4. **The Zig port** — `zig test tests.zig`, asserting the same file from the reference's own language.

## Using it

```xml
<dependency>
    <groupId>hr.hrg</groupId>
    <artifactId>wyhash</artifactId>
    <version>1.2.0</version>
</dependency>
```

**Java 22 or newer.** The `MemorySegment` input cannot exist earlier — `java.lang.foreign` is final in 22 — and
`1.0.0`'s floor of 18 therefore no longer applies. The zero-allocation `String` path additionally wants
`java.base/java.lang` opened to the unnamed module (`--add-opens java.base/java.lang=ALL-UNNAMED`); without it the
implementation falls back to `toCharArray()` and stays correct, but allocates (see
[`doc/zero-allocation.md`](doc/zero-allocation.md) § 2).

```java
// One-shot: the same bytes hash the same wherever they live.
long h1 = Wyhash64.hash(0, bytes);                        // byte[]
long h2 = Wyhash64.hash(0, bytes, offset, length);        // a slice
long h3 = Wyhash64.hash(0, byteBuffer);                   // ByteBuffer
long h4 = Wyhash64.hash(0, memorySegment, offset, length);// MemorySegment: mmap, arena, off-heap
long h5 = Wyhash64.hash(0, "some text");                  // String, no copy (see the note below)
long h6 = Wyhash64.hash(0, chars, offset, length);        // char[] / CharSequence

String hex = Wyhash64.hex(h1);                            // 16 lowercase hex characters

// Streaming: any mix of the inputs above, in any chunking, equals one-shot.
Wyhash64.Streaming streaming = new Wyhash64.Streaming(0);
streaming.update(inputStream, 0, 12_288);
streaming.update(mappedFile);
streaming.updateByte((byte) '\n');
long h7 = streaming.finalHash();
streaming.reset(0);                                       // reusable, and finalHash() does not consume it
```

Two things worth knowing before the API surprises you:

- **`hash(seed, String)` hashes the string's *internal* encoding** (Latin-1 one byte per character, or the
  UTF-16 bytes) — that is what makes it allocation-free. It is *not* the UTF-8 bytes of the string, so a caller
  that wants a name or a file's text hashed as UTF-8 passes `getBytes(UTF_8)`. The vectors' `text` cases are
  UTF-8 byte sequences for exactly this reason.
- **The hash does not normalise anything.** Line endings, encodings and absolute paths are the caller's decision;
  a port that folded them in would make two different byte sequences hash alike for every consumer.

## The vectors, and why they are generated

`conformance/wyhash-vectors.json` is the machine-checkable form of the definition, and it is **generated from
the reference** — `conformance/gen-vectors.zig` computes every value by calling `std.hash.Wyhash`. A vector file
filled in from a port's output would only prove that the port agrees with itself.

The cases: text fixtures (the library-produced goldens among them), pattern cases over the lengths that choose
the algorithm's branches up to one mebibyte, seeded cases including both extremes of the seed range, and **the
reference's own acceptance vectors** — the `test` block of Zig's `lib/std/hash/wyhash.zig`, reproduced by
calling the builtin rather than by transcribing its expected values.

```sh
# from the project root, with Zig 0.17+ (check-ports.mjs resolves and verifies the toolchain)
zig run conformance/gen-vectors.zig > conformance/wyhash-vectors.json
zig run conformance/gen-vectors.zig -- java > src/test/java/hr/hrg/wyhash/WyhashVectors.java
```

`check-ports.mjs` diffs both artefacts against a fresh run, so the two cannot describe different vectors, and the
`reference.zigVersion` field records which Zig produced the committed file.

---

## Zig's Wyhash Variant

### Why Zig uses Wyhash

Zig adopts Wyhash as its default hashing algorithm for `std.AutoHashMap` and `std.StringHashMap` because it
provides an exceptional balance of:

- **Performance**: Extremely fast for both short keys and large bulk data.
- **Quality**: Passes all SMHasher tests, indicating excellent collision resistance and distribution.
- **Portability**: Pure 64-bit/32-bit compatible without requiring specialized hardware instructions (like AES-NI).

### The "Zig Variant" (Final3)

Zig's implementation corresponds to **Wyhash v3** (also known as `wyhash_final3`). It uses the standard set of
"secret" constants defined in the final revisions of the algorithm:

| Constant | Value                |
| :------- | :------------------- |
| `p0`     | `0xa0761d6478bd642f` |
| `p1`     | `0xe7037ed1a0b428db` |
| `p2`     | `0x8ebc6af09c88c6e3` |
| `p3`     | `0x589965cc75374cc3` |

Zig chose this specific iteration because it was the most stable and performant version that maintained full
compatibility with stream-based processing before Version 4 introduced structural changes that made streaming
more complex.

---

## Wyhash Version History

The Wyhash algorithm has evolved through several major iterations:

1.  **v1**: The original release. Extremely fast but later found to have minor security vulnerabilities (predictability).
2.  **v2**: Introduced security enhancements to address v1 issues, with a slight trade-off in raw speed.
3.  **v3 (Final3)**: Doubled the bulk hashing speed of v2 while maintaining security. This is the version most
    commonly implemented in modern language standard libraries (including Zig).
4.  **v4 (Final4)**: Optimized further but changed the algorithm's structure (requiring the total length at the
    start), which complicates streaming implementations.
5.  **Rapidhash**: The "official successor" to Wyhash. It improves performance by ~6% and offers even lower
    collision rates. It is designed to be the next generation of general-purpose hashing.

`wyhash` is a extremely fast, portable, and high-quality non-cryptographic hash function. It passes Smhasher
tests and is designed to be efficient on modern 64-bit CPUs.

Version v3 is used here as it aligns with Zig and Bun. It is good for file hashing to check for modifications. It
should not be used for hash tables or other applications where collision resistance is critical.

## Algorithm Overview

The core of Wyhash relies on a mixing function (often called `mum` for MUltiply and Mix) that takes two 64-bit
numbers, calculates their 128-bit product, and then XORs the upper and lower 64-bit halves together to produce a
64-bit result.

### Why 64-bit?

Wyhash is specifically optimized for modern 64-bit processors. By using native 64-bit arithmetic (especially
64x64 -> 128-bit multiplication) and processing data in larger chunks, it achieves extremely high throughput
without relying on platform-specific SIMD instructions (like AVX or NEON). This design ensures both high speed
and excellent portability across different architectures (x86_64, AArch64).

### 1. Initialization

The algorithm uses a 256-bit secret (four 64-bit constants) and a random seed. The state is initialized by mixing
the seed with the secret.

### 2. Block Processing

The input data is processed in **48-byte blocks**.
For each block:

- The state is updated using the secret and the input data.
- The input is consumed in three 16-byte stripes, effectively updating the internal verify state.

### 3. Finalization

After processing all 48-byte blocks:

- Any remaining bytes are handled (with special care for small keys < 16 bytes).
- A final round of mixing is performed using the remaining state, the total length of the input, and the secrets
  to produce the final 64-bit hash.

### 4. Streaming (Chunk-by-Chunk) Hashing

When hashing large files or streams of unknown size, Wyhash can be implemented using a streaming pattern (`init`,
`update`, `final`). This is crucial for maintaining a low memory footprint as it avoids loading the entire file
into memory.

1.  **State Management**: An internal state object tracks the three 64-bit stripe variables (`see0`, `see1`,
    `see2`), the total bytes processed, and a small buffer (48 bytes) to handle partial blocks.
2.  **Buffering**: Data is fed into the `update` function in any size. If the current input plus the internal
    buffer exceeds 48 bytes, full 48-byte blocks are processed immediately.
3.  **Partial Blocks**: Any data that doesn't form a full 48-byte block is stored in the internal buffer to be
    combined with the next `update` call or handled during `final`.
4.  **Finalization**: The final call processes any remaining bytes in the buffer as the "tail" and performs the
    final mix using the accumulated total length.

### 5. Buffer Optimization (12KB Alignment)

To maximize performance during streaming, the read buffer size should ideally be a multiple of both the
underlying storage block size and the hash function's block size.

In the implementation that motivated this buffering, we use a **12KB (12,288 bytes)** buffer:

- **Disk I/O Alignment**: 12KB is a multiple of **4KB**, which is the standard physical block size for modern
  hard drives and SSDs (Advanced Format). This ensures that each read operation captures a whole number of
  physical sectors, reducing overhead.
- **Wyhash Alignment**: 12KB is a multiple of **48 bytes** (12,288 / 48 = 256 blocks). This means every buffer
  read contains an exact number of Wyhash blocks.
- **Zero-Copy Efficiency**: Because the buffer aligns perfectly with the 48-byte stripes, the `update` function
  can process the entire chunk directly without having to copy partial data into an internal "leftover" buffer,
  significantly reducing memory-to-memory copies during large file transfers.

---

## Implementation Details: Java vs Zig

The Java implementation in `Wyhash64.java` is a direct port of the Zig implementation in the standard library’s
`std/hash/wyhash.zig` (which itself tracks the upstream C++ implementation).

### 1. The Secret

Both implementations use the same default 256-bit secret.

**Zig:**

```zig
const secret = [_]u64{
    0xa0761d6478bd642f,
    0xe7037ed1a0b428db,
    0x8ebc6af09c88c6e3,
    0x589965cc75374cc3,
};
```

**Java:**

```java
private static final long[] DEFAULT_SECRET = {
    0xa0761d6478bd642fL, 0xe7037ed1a0b428dbL, 0x8ebc6af09c88c6e3L, 0x589965cc75374cc3L
};
```

#### Origin of Default Secret

The default hex constants used in both implementations (`0xa0761d6478bd642f`, etc.) are the standard default
secrets defined in the original Wyhash C++ implementation (`wyhash.h`). They are chosen as large pseudo-prime
numbers to ensure good bit mixing properties and are used when no custom secret is provided.

You can view the source file here: [wyhash.h on GitHub](https://github.com/wangyi-fudan/wyhash/blob/master/wyhash.h).

### 2. The Mix (Mum) Function

This is the most interesting difference due to language capabilities. Wyhash requires **unsigned** 64x64 ->
128-bit multiplication.

**Zig** has native support for `u128` and unsigned arithmetic, making the implementation straightforward:

```zig
inline fn mum(a: *u64, b: *u64) void {
    const x = @as(u128, a.*) *% b.*;
    a.* = @as(u64, @truncate(x));
    b.* = @as(u64, @truncate(x >> 64));
}

inline fn mix(a_: u64, b_: u64) u64 {
    var a = a_;
    var b = b_;
    mum(&a, &b);
    return a ^ b;
}
```

**Java**

```java
private static long mix(long a, long b) {
    long low = a * b;
    // Java 9+ (standard in Java 17)
    // long high = Math.multiplyHigh(a, b) + ((a >> 63) & b) + ((b >> 63) & a);

    // Java 18+ efficient intrinsic
    long high = Math.unsignedMultiplyHigh(a, b);
    return low ^ high;
}
```

> [!TIP]
> **Java Version Compatibility**:
> This library requires **Java 22+**, because the `MemorySegment` input uses `java.lang.foreign` (final in 22).
> The mixing intrinsic itself needs only Java 18 (`Math.unsignedMultiplyHigh`); to target 18–21 you would drop
> the `MemorySegment` overloads and keep the rest unchanged.
>
> Java older than 18 only supports signed primitives. To emulate unsigned 64-bit multiplication and get the high
> 64 bits of the 128-bit result, `Math.multiplyHigh` is used with a correction factor. `Math.multiplyHigh` treats
> operands as signed. To get the unsigned result, we add one operand if the other is negative (interpreted as
> signed), which corresponds to the `(a >> 63) & b` logic.

### 3. Reading Data (Endianness)

Wyhash relies on Little Endian reads.

**Zig** uses `std.mem.readInt` with explicit little endian:

```zig
inline fn read(comptime bytes: usize, data: []const u8) u64 {
    // ...
    return @as(u64, std.mem.readInt(T, data[0..bytes], .little));
}
```

**Java** uses `VarHandle` for efficient little-endian memory access — and `ValueLayout` for a `MemorySegment`,
which is what makes the memory-mapped and off-heap input copy-free:

```java
private static final VarHandle LONG_HANDLE = MethodHandles.byteArrayViewVarHandle(long[].class, ByteOrder.LITTLE_ENDIAN);

private static long getLong(byte[] b, int off) {
    return (long) LONG_HANDLE.get(b, off);
}

private static final ValueLayout.OfLong SEGMENT_LONG =
        ValueLayout.JAVA_LONG_UNALIGNED.withOrder(ByteOrder.LITTLE_ENDIAN);
```

### 4. Main Loop

Both iterate in 48-byte chunks.

**Zig:**

```zig
while (i + 48 < input.len) : (i += 48) {
    self.round(input[i..][0..48]);
}

// The round function implementation:
inline fn round(self: *Wyhash, input: *const [48]u8) void {
    inline for (0..3) |i| {
        const a = read(8, input[8 * (2 * i) ..]);
        const b = read(8, input[8 * (2 * i + 1) ..]);
        self.state[i] = mix(a ^ secret[i + 1], b ^ self.state[i]);
    }
}
```

**Java:**

```java
while (i > 48) {
    see0 = mix(getLong(data, p) ^ secret1, getLong(data, p + 8) ^ see0);
    see1 = mix(getLong(data, p + 16) ^ secret2, getLong(data, p + 24) ^ see1);
    see2 = mix(getLong(data, p + 32) ^ secret3, getLong(data, p + 40) ^ see2);
    p += 48;
    i -= 48;
}
```

*Note: The Java implementation shown here is the static `hash` method which processes bulk data similarly to the
`update` + `round` logic in Zig's streaming implementation, but inline.*

### 5. Finalization

Both use the total length and final states to produce the hash.

**Zig:**

```zig
inline fn final2(self: *Wyhash) u64 {
    self.a ^= secret[1];
    self.b ^= self.state[0];
    mum(&self.a, &self.b);
    return mix(self.a ^ secret[0] ^ self.total_len, self.b ^ secret[1]);
}
```

**Java:**

```java
private static long finish(long a, long b, long seed, long len) {
    long _a = a ^ DEFAULT_SECRET[1];
    long _b = b ^ seed;
    long low = _a * _b;
    long high = Math.multiplyHigh(_a, _b) + ((_a >> 63) & _b) + ((_b >> 63) & _a);
    return mix(low ^ DEFAULT_SECRET[0] ^ len, high ^ DEFAULT_SECRET[1]);
}
```

The Java `finish` method essentially inlines the `mum` + `mix` operations seen in Zig's `final2`.

---

## Smhasher Tests

Smhasher is a comprehensive test suite designed to evaluate the quality, collision resistance and performance of
non-cryptographic hash functions. It runs a battery of tests to ensure the hash function produces a good
distribution and doesn't have obvious biases or collision vulnerabilities.

Wyhash passes all tests in the Smhasher suite.

For more details, visit the [Smhasher repository](https://github.com/rurban/smhasher).

---

## Seed and Determinism

While Wyhash is designed to accept a seed (which is useful for hash tables to prevent HashDoS attacks), it can
also be used as a deterministic checksum for file verification.

To use Wyhash for verification (e.g., checking if a file has changed), you simply need to **use a fixed constant
seed** (like `0`) for all calculations.

- **Random Seed**: Used for in-memory hash maps (non-deterministic across runs).
- **Fixed Seed**: Used for persistent storage, checksums, and signatures (deterministic).

Both the Java and Zig implementations allow you to provide a specific seed during initialization or the one-shot
hash call.

## When not to use Wyhash V3

If you are using WyHash to build a HashMap that accepts untrusted user input (e.g., a web server's header keys),
an attacker could theoretically find "bad seeds" or "bad secrets" that force these multiplications to zero.

- By forcing the hash to zero, they cause every single input to land in the same hash bucket.
- This turns a O(1) lookup into a O(n) lookup, allowing a tiny amount of traffic to DDoS your CPU.

For such use cases you should use Wyhash V4.2 that is considered v4final.

If you are looking for further improvements, check the successor <https://github.com/Nicoshev/rapidhash>.

---

## Publishing

Maven releases go through [`pom-release.xml`](pom-release.xml), never a bare `mvn deploy`; [publishing.md](publishing.md)
has the prerequisites (JDK 22+, real Maven 3.9.9, the `central` token and GPG), the commands and the two-POM guard.
The same file covers the npm package (`@hrg/wyhash`) and the Zig source.

`hr.hrg:wyhash:1.2.0` is on Maven Central and `@hrg/wyhash@1.2.0` is on npm. fs-meta pins the Java artifact and
imports the scoped npm package; fs-meta 0.3.7 is the published release that consumes it.

## License

MIT — see [`LICENSE.txt`](LICENSE.txt). That covers everything in this repository: `1.0.0`'s Java
implementation, the implementation that grew out of it (`1.2.0`), the JavaScript and Zig ports, the generator and
the generated vectors. The Java port arrived from the dia-log project on 2026-10-16 together with its design
document and ADR; it is MIT here like the rest, and `doc/adr/005-wyhash64-deterministic-hashing.md` plus
[`doc/zero-allocation.md`](doc/zero-allocation.md) keep the attribution and the decision history. Every source file
carries an `SPDX-License-Identifier: MIT` header, and the generated Java table
(`src/test/java/hr/hrg/wyhash/WyhashVectors.java`) is emitted with the same pair, so a copy of any file says what
it is under without a lookup.