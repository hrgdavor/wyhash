# wyhash conformance vectors

`wyhash-vectors.json` is the contract every port of this project asserts. It is **generated from the
reference** — `gen-vectors.zig` computes each value with `std.hash.Wyhash`, the Zig builtin — so the numbers in
it come from the definition rather than from a port, which is the only thing that makes a vector file worth
having.

```sh
# from the project root, with Zig 0.17+ (check-ports.mjs resolves and verifies the toolchain)
zig run conformance/gen-vectors.zig > conformance/wyhash-vectors.json
zig run conformance/gen-vectors.zig -- java > src/test/java/hr/hrg/wyhash/WyhashVectors.java
```

**Two artefacts, one generator, and `check-ports.mjs` diffs both.** The JSON is what the JavaScript and Zig ports
parse. The Java table is the same cases as generated Java source, because the Java port is pure JDK — there is no
JSON reader to borrow, and adding a dependency for a test resource would defeat the point of a library with no
runtime dependency. The generator's `-- java` mode emits text fixtures as **hex**, which is what a `text` case
is: the fixture's UTF-8 byte sequence, stated without an escaping rule that could disagree with the JSON.

## What is in the file

| Member             | Count | What it pins                                                                   |
| ------------------ | ----- | ------------------------------------------------------------------------------ |
| `reference`        |       | `variant: "zig-builtin"`, `builder: "std.hash.Wyhash"`, `seed: 0`, and the Zig version it was generated under |
| `cases`            | 33    | 15 `text` fixtures — the library-produced golden vectors among them — and 18 `pattern` cases over the lengths that choose the algorithm's branches: 4, 7, 8, 15, 16, 17, 31, 32, 47, 48, 49, 64, 100, 255, 256, 1000, 10 800, and 1 048 576 |
| `seedCases`        | 7     | the same inputs under seeds `1`, `0x9E3779B97F4A7C15` and `0xFFFFFFFFFFFFFFFF` |

A case's bytes are either:

- **`text`** — the fixture's UTF-8 bytes, which is what a name or a text file's content is hashed as; or
- **`pattern`** — `{"kind": "index7plus3", "length": n}`, meaning `byte[i] = (i * 7 + 3) & 0xFF`. A pattern
  reaches a mebibyte without a megabyte of hex in the file, and it is three lines in any language.

A case's value is `wyhash64` as 16 lowercase hex characters: unsigned, zero-padded, which is how
`checksum` columns and `files.meta` fields in this repository are written.

A **seed in a `seedCase` is a string of sixteen hex characters**, not a number, because `0x9E3779B97F4A7C15`
does not survive a JSON number's double precision. The reference's default seed is the number `0`.

## Why the cases are shaped this way

- **The text fixtures are the library's own goldens.** They were produced by `hr.hrg.wyhash:wyhash:1.0.0` (the
  same ten vectors `hipster-entity-tooling`'s `ContentHashTest` pins its vendored copy to), and the builtin
  reproduces every one of them — measured, and that agreement is the premise of this project. So a port that
  asserts these cases is anchored to both the library the Java side used before the merge and the builtin the
  merged port wraps. A `text` case is its **UTF-8 byte sequence**: Java's `hash(seed, String)` hashes the
  string's internal encoding instead, which is why the generated Java table carries hex and `WyhashVectorCheck`
  hashes `getBytes(UTF_8)` for it.
- **`pattern` cases exist because a hash's branches are chosen by length.** A table of hand-written strings
  would leave the 48-byte block loop, the 16-byte tail loop and the multi-block path pinned only as far as the
  longest string somebody happened to type. The 1 048 576-byte case also pins the property a streaming
  implementation must have: `update` in pieces, then `final`, equals one-shot over the whole input.
- **`seedCases` exist so a port cannot ignore its seed.** Every other case is seed 0, which is the seed this
  repository's tables use; a port that dropped the parameter and hard-coded the initial state would pass all of
  them.

## Keeping it honest

`bun check-ports.mjs` re-runs this generator and compares its output with **both** committed artefacts —
this JSON and `src/test/java/hr/hrg/wyhash/WyhashVectors.java`. That check exists because the failure mode is
silent: if a Zig upgrade changes `std.hash.Wyhash`, the committed vectors become a description of yesterday's
algorithm, and every port that asserts them still "passes" — against a definition nobody uses any more. A
mismatch is reported with the first differing line, and the `reference.zigVersion` field records which Zig
produced the file that is checked in. Regenerating under **Zig 0.17** produced a file identical to the 0.16 one
apart from that field — the values are stable across the upgrade, and this check is what proves it.