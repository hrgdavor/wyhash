# wyhash, as this project defines it

`wyhash` is one 64-bit non-cryptographic hash, chosen once and implemented in as many languages as its
consumers need, so that a table written by one tool can be compared with a table written by another. This
document is the definition: what the reference is, what a port must expose, and what the shared vectors pin.

**The reference is the Zig builtin, `std.hash.Wyhash`.** That is a decision with a reason: the Java
implementations in circulation — this project's own `1.0.0`, which `java-watch-core`'s `ChecksumDatabase`, the
agent's `MetadataCache` and the engine's `ContentHash` use, and the copies vendored into other projects — were
all written to follow it, and the builtin reproduces every library-produced golden vector this project already
pins. Taking the builtin as the definition therefore makes "the reference" and "what the Java code in the wild
does" the same statement rather than two hopes that meet in the middle.

`conformance/wyhash-vectors.json` is the machine-checkable form of that decision, and it is **generated from
the builtin** (`conformance/gen-vectors.zig`), not from any port.

## 1. The algorithm

The parameters, so that a port can be written or audited without reading another port:

| Item            | Value                                                                                              |
| --------------- | -------------------------------------------------------------------------------------------------- |
| Secrets         | `0xa0761d6478bd642f`, `0xe7037ed1a0b428db`, `0x8ebc6af09c88c6e3`, `0x589965cc75374cc3`             |
| Seed            | initialised as `seed ^ mix(seed ^ secret[0], secret[1])`, where `mix(a, b)` is the low 64 bits of `a * b` XOR the high 64 bits |
| Short input     | `len <= 16`: two overlapping four-byte groups at offsets `0`, `(len >> 3) << 2`, `len - 4` and `len - 4 - ((len >> 3) << 2)`; for `len < 4`, the three single bytes at `0`, `len >> 1`, `len - 1` |
| Block loop      | while more than 48 bytes remain: three `mix` steps over 48 bytes with secrets 1–3, folded together |
| Tail loop       | while more than 16 bytes remain: one `mix` step per 16 bytes                                       |
| Finish          | the last 16 bytes as `a`, `b`; `mix(low ^ secret[0] ^ len, high ^ secret[1])` over the **unsigned** 128-bit product of `a ^ secret[1]` and `b ^ state` |
| Result          | an unsigned 64-bit value                                                                           |

Two details are where a rewrite from memory goes wrong, and both are covered by vectors: the short-input
offsets are `(len >> 3) << 2` rather than a constant, and `finish` needs the **unsigned** high half of the
product (JavaScript's `Math.imul` stops at 32 bits, Java's `multiplyHigh` is signed and needs correcting).

## 2. What a port must expose

The vocabulary is aligned across languages on purpose — a reader who has seen one port can read the next:

| Name           | Java                                                     | JavaScript                                 | Zig                                    |
| -------------- | -------------------------------------------------------- | ------------------------------------------ | -------------------------------------- |
| the seed       | `Wyhash64.SEED` (`0`)                                    | `SEED` (`0n`)                              | `SEED` (`0`)                           |
| one-shot hash  | `hash(long seed, byte[] bytes)`                          | `wyhash64(bytes, seed)` → `BigInt`         | `hash(seed, bytes)` → `u64`            |
| one-shot slice | `hash(seed, bytes, off, len)`, `hash(seed, ByteBuffer[, off, len])`, `hash(seed, MemorySegment[, off, len])` | `wyhash64(bytes.subarray(off, off + len))` | `hash(seed, bytes[off..][0..len])` |
| hex form       | `Wyhash64.hex(long)` → `String`                          | `wyhash64Hex(bytes, seed)`                 | `std.fmt` `{x:0>16}`                   |
| streaming      | `Wyhash64.Streaming` (`update` / `finalHash` / `reset`)  | *(none yet — see below)*                   | `Streaming` (`update` / `final`)       |
| pattern bytes  | the `patternLength` of a generated vector                | `patternBytes(length)`                     | `fillPattern(bytes)`                   |

A port is **done** when it asserts every case and every seed case in the shared vectors, and the streaming form
it exposes equals the one-shot form over the `pattern-1048576` input. The JavaScript port currently has no
streaming API: no consumer streams a hash from JavaScript yet, and an untested convenience is worse
than an absent one — the vectors pin the value it will have to produce when it is added.

### The one API difference that is not a porting detail: text

A `text` case in the vectors is **the fixture's UTF-8 byte sequence**, and a port hashes those bytes. Java's
`hash(seed, String)` does *not* hash a string's UTF-8 encoding — it hashes the string's **internal** encoding
(Latin-1 one byte per char, UTF-16 two), which is the whole point of the zero-allocation paths in
`doc/zero-allocation.md`. So a port whose vectors test uses `hash(seed, someString)` is testing a different
byte sequence for any non-ASCII fixture, and the Java check therefore hashes `text.getBytes(UTF_8)`
(`WyhashVectorCheck` says so at the point it does it). The `utf8` fixture — `héllo\n` — is in the table to make
that failure loud rather than silent.

**The hash does not normalise anything.** Line-ending normalisation — `\r\n` and a lone `\r` to `\n` — is a
*content* decision taken above this layer (`fs-meta` records it per entry, `ChecksumDatabase` decides by file
type), and a port that folded it in here would make two different byte sequences hash alike for every caller,
including the ones that wanted the raw bytes. The hash's contract is: these bytes, this seed, that value.

## 3. The vectors

`conformance/wyhash-vectors.json`:

| Member       | What it pins                                                                   |
| ------------ | ------------------------------------------------------------------------------ |
| `reference`  | `variant: "zig-builtin"`, `builder: "std.hash.Wyhash"`, `seed: 0`, and the Zig version the file was generated under |
| `cases` (33) | text fixtures — the library-produced golden vectors among them — plus `pattern` cases over the lengths that choose the algorithm's branches |
| `seedCases`  | the same inputs under seeds `1`, `0x9E3779B97F4A7C15` and `0xFFFFFFFFFFFFFFFF` |

Two choices in that file are deliberate:

- **A case's bytes are either `text` (UTF-8) or a `pattern`** with `{"kind": "index7plus3", "length": n}`, whose
  bytes are `byte[i] = (i * 7 + 3) & 0xFF`. A table of text fixtures alone would pin the block and tail paths
  only as far as the longest string somebody happened to write; a pattern reaches one mebibyte without putting
  a megabyte of hex in the file, and it is three lines in any language.
- **A seed is written as sixteen hex characters**, in the `seedCases`, because `0x9E3779B97F4A7C15` does not
  survive a JSON number's double precision. The default seed stays the number `0`.

## 4. Status of the ports

| Port   | Where                          | State |
| ------ | ------------------------------ | ----- |
| Zig    | `zig/wyhash.zig`               | **done** — and it *is* the reference: a thin wrapper over `std.hash.Wyhash`, because a transcription of the reference would be a second thing to keep equal to it. Tests: `tests.zig`. Built and tested with **Zig 0.17** |
| JS     | `js/wyhash64.mjs`              | **done** — a from-scratch implementation in BigInt arithmetic, asserted against the vectors *and* the library golden vectors |
| Java   | `src/main/java/hr/hrg/wyhash/` | **done** — grown out of this project's `1.0.0` (see `doc/adr/005-wyhash64-deterministic-hashing.md`), with its zero-allocation `String` paths, `char[]`/`CharSequence` handling, streaming form and **144 tests**. A `MemorySegment` path is the newest addition, for callers that already hold bytes off-heap |

The Java port publishes the coordinates its consumers already resolve — `hr.hrg:wyhash` — at `1.1.0`,
which supersedes the published `1.0.0`: the same algorithm, the same values (every one of them in the vector
file), one implementation to maintain. The JavaScript port is published separately as `@hrg/wyhash`. A consumer
that pinned `1.0.0` gets the same values from `1.1.0` and a larger API; a consumer that vendored a copy, or wrote
its own, can retire it against the vectors this project generates — the retirement itself is that project's change,
not this one's.

## 5. Checking it

```sh
bun check-ports.mjs    # reference integrity (both generated artefacts), the JS port, the Java port, the Zig port
bun test js            # the JavaScript port's tests (6)
mvn package            # the Java port's tests (144; surefire opens java.lang for the zero-alloc paths)
zig test tests.zig     # the Zig port's tests (run from this directory, Zig 0.17+)
```

`check-ports.mjs` resolves its toolchains itself — `WYHASH_ZIG` then `ZIG` then a Zig release directory then
`PATH`, verified to be at least **0.17**; `WYHASH_JDK` then `JAVA_HOME` then `PATH`, verified to be at least
**22** — and re-runs the generator,
comparing its output with **both** committed artefacts, the JSON and the generated Java table. If a Zig upgrade
changes `std.hash.Wyhash`, that check fails *before* any port can pass against yesterday's definition; if the
table and the JSON ever describe different vectors, it fails for the same reason. Regenerating by hand:

```sh
zig run conformance/gen-vectors.zig > conformance/wyhash-vectors.json
zig run conformance/gen-vectors.zig -- java > src/test/java/hr/hrg/wyhash/WyhashVectors.java
```