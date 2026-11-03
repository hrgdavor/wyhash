#!/usr/bin/env bun
// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Davor Hrg
//
// The JavaScript port's tests:
//
//   bun test wyhash/js
//
// Every value comes from `conformance/wyhash-vectors.json`, which is generated from the reference
// (`std.hash.Wyhash`) — and the library-produced golden vectors are asserted too, because they are what the
// existing Java implementations were written against and the whole premise of this project is that the two
// are the same statement.

import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, test } from 'node:test';

import {
  LIBRARY_GOLDEN_VECTORS, assertLibraryGoldenVectors, patternBytes, wyhash64, wyhash64Hex,
} from './wyhash64.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const vectors = JSON.parse(readFileSync(join(here, '..', 'conformance', 'wyhash-vectors.json'), 'utf8'));

const bytesOf = (vector) => (vector.text !== undefined
  ? Buffer.from(vector.text, 'utf8')
  : patternBytes(vector.pattern.length));

const seedOf = (vector) => (vector.seed === undefined ? 0n : BigInt(`0x${vector.seed}`));

describe('wyhash64, the JavaScript port', () => {
  test('the reference the vectors name is the variant this port implements', () => {
    assert.equal(vectors.reference.variant, 'zig-builtin');
    assert.equal(vectors.reference.builder, 'std.hash.Wyhash');
    assert.equal(vectors.reference.seed, 0);
    assert.ok(vectors.reference.zigVersion.length > 0, 'the generator records the version it ran under');
  });

  test('the library-produced golden vectors', () => {
    assert.equal(assertLibraryGoldenVectors(), LIBRARY_GOLDEN_VECTORS.length);
  });

  test('every case in the reference vector file', () => {
    let checked = 0;
    for (const vector of vectors.cases) {
      assert.equal(wyhash64Hex(bytesOf(vector)), vector.wyhash64,
        `case '${vector.label}' (${vector.text !== undefined ? 'text' : `pattern ${vector.pattern.kind} ${vector.pattern.length}`})`);
      checked++;
    }
    assert.ok(checked >= 30, `expected at least 30 cases, got ${checked}`);
  });

  test('the seeded cases, so this port cannot ignore its seed', () => {
    for (const vector of vectors.seedCases) {
      assert.equal(wyhash64Hex(Buffer.from(vector.text, 'utf8'), seedOf(vector)), vector.wyhash64,
        `case '${vector.label}'`);
    }
    // The point of those cases, stated as a property: a different seed is a different answer.
    const text = Buffer.from('line1\nline2\n', 'utf8');
    assert.notEqual(wyhash64Hex(text, 1n), wyhash64Hex(text, 0n));
  });

  test('a view into a larger buffer hashes like the bytes themselves', () => {
    // A real risk for this port: `wyhash64` builds a DataView from the argument, and a Buffer that is a view
    // has a non-zero `byteOffset`. Hashing the wrong window would still pass every vector above, because the
    // vectors hand it a view at offset 0.
    const pattern = patternBytes(1000);
    const padded = Buffer.concat([Buffer.from([0xff, 0xff, 0xff]), pattern, Buffer.from([0xff])]);
    const view = padded.subarray(3, 3 + pattern.length);
    assert.equal(view.byteOffset, 3);
    assert.equal(wyhash64Hex(view), wyhash64Hex(Buffer.from(pattern)));
  });

  test('an empty input is not a special case that returns zero', () => {
    assert.equal(wyhash64Hex(Buffer.alloc(0)), '0409638ee2bde459');
    assert.notEqual(wyhash64(Buffer.alloc(0)), 0n);
  });
});