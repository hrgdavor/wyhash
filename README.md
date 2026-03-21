# Wyhash Java Implementation (Zig-Compatible)

A standalone Java implementation of the **Wyhash** algorithm, specifically the variant used by the **Zig** programming language's standard library (`std.hash.Wyhash`).

> [!IMPORTANT]
> This implementation is intended for **file change tracking** and general-purpose non-cryptographic hashing. It is **not** meant for security-sensitive cryptographic applications.

## Zig's Wyhash Variant

### Why Zig uses Wyhash
Zig adopts Wyhash as its default hashing algorithm for `std.AutoHashMap` and `std.StringHashMap` because it provides an exceptional balance of:
- **Performance**: Extremely fast for both short keys and large bulk data.
- **Quality**: Passes all SMHasher tests, indicating excellent collision resistance and distribution.
- **Portability**: Pure 64-bit/32-bit compatible without requiring specialized hardware instructions (like AES-NI).

### The "Zig Variant" (Final3)
Zig's implementation corresponds to **Wyhash v3** (also known as `wyhash_final3`). It uses the standard set of "secret" constants defined in the final revisions of the algorithm:

| Constant | Value |
| :--- | :--- |
| `p0` | `0xa0761d6478bd642f` |
| `p1` | `0xe7037ed1a0b428db` |
| `p2` | `0x8ebc6af09c88c6e3` |
| `p3` | `0x589965cc75374cc3` |

Zig chose this specific iteration because it was the most stable and performant version that maintained full compatibility with stream-based processing before Version 4 introduced structural changes that made streaming more complex.

---

## Wyhash Version History

The Wyhash algorithm has evolved through several major iterations:

1.  **v1**: The original release. Extremely fast but later found to have minor security vulnerabilities (predictability).
2.  **v2**: Introduced security enhancements to address v1 issues, with a slight trade-off in raw speed.
3.  **v3 (Final3)**: Doubled the bulk hashing speed of v2 while maintaining security. This is the version most commonly implemented in modern language standard libraries (including Zig).
4.  **v4 (Final4)**: Optimized further but changed the algorithm's structure (requiring the total length at the start), which complicates streaming implementations.
5.  **Rapidhash**: The "official successor" to Wyhash. It improves performance by ~6% and offers even lower collision rates. It is designed to be the next generation of general-purpose hashing.

---

## Usage

This project provides a standalone Java implementation that matches the output of Zig's `std.hash.Wyhash.hash(seed, data)`. 

(Include implementation details or class references here once added)
