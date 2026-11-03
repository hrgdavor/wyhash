# Architecture Decision Records

This directory holds the Architecture Decision Records that are **this project's own** — chiefly the decision
that produced the Java port, copied here from the project where it was made when the implementation moved
(`doc/AGENTS.md`-style guidance for writing one is *not* copied: each project states its own).

| ADR                                              | Title                              | Status   | Impl. Status                        |
| ------------------------------------------------ | ---------------------------------- | -------- | ----------------------------------- |
| [005](005-wyhash64-deterministic-hashing.md)     | Wyhash64 for deterministic hashing | Accepted | Implemented (moved here 2026-10-16) |

Two ADRs that a reader of this project will look for live somewhere else, on purpose:

- **Dia-Log's ADR 005** is the original of the copy above, and **dia-log's ADR 014** records the extraction from
  dia-log's side — its decision to depend on `hr.hrg:wyhash` rather than keep a copy of the class.
- This project's own contract is not an ADR: it is [`WYHASH.md`](../../WYHASH.md) (the definition, the ports,
  the vectors) with [`conformance/README.md`](../../conformance/README.md) for how the vectors are produced.

A decision that changes what `std.hash.Wyhash` means for this project — a different variant, a different
reference, a seed convention — earns an ADR here. A new input kind (another memory type, another string
representation) is API surface and belongs in `WYHASH.md` unless it changes a value.