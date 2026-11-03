// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Davor Hrg
package hr.hrg.wyhash;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.lang.foreign.MemorySegment;
import java.util.HexFormat;

import org.junit.jupiter.api.Test;

/**
 * The Java port against the reference's vectors — the half of this project's contract that has nothing to do
 * with the other ports' API surface.
 *
 * <p>The table is <strong>generated</strong> ({@code WyhashVectors}, from
 * {@code conformance/gen-vectors.zig} → {@code std.hash.Wyhash}), so this test cannot drift from the
 * reference by being edited, and {@code check-ports.mjs} asserts the same class from outside a Maven run. The
 * assertions themselves live in {@link WyhashVectorCheck} so both entry points share one implementation.</p>
 *
 * <p>Two of the assertions here are about the table rather than a value: that it is big enough to be the
 * reference's (a truncated table must fail, not pass vacuously), and that every case's expected value is 16
 * lowercase hex characters — the form every table in this family is written in.</p>
 */
class WyhashReferenceVectorsTest {

    @Test
    void everyReferenceCaseMatches() {
        assertEquals("", WyhashVectorCheck.checkAll(), "the port must agree with the reference's own table");
    }

    @Test
    void theTableIsTheReferenceSizeAndShape() {
        assertTrue(WyhashVectors.CASES.length >= 40,
                "the reference generates 40 cases; a table this small would pass vacuously");
        int seeded = 0;
        for (WyhashVectors.Vector vector : WyhashVectors.CASES) {
            assertTrue(vector.expected().matches("[0-9a-f]{16}"),
                    "a vector value is 16 lowercase hex characters: " + vector.label() + " -> " + vector.expected());
            assertTrue(vector.isPattern() || vector.hex() != null,
                    "a case has either a byte sequence or a pattern: " + vector.label());
            if (vector.seed() != 0) {
                seeded++;
            }
        }
        assertTrue(seeded >= 5, "the table must carry seeded cases, so a port cannot ignore its seed");
    }

    @Test
    void theTableCoversTheLengthsThatChooseTheAlgorithmBranches() {
        // 16/17, 48/49 and the 16-byte tail are where a rewrite goes wrong; the reference includes them, and
        // this test fails if a regeneration ever drops them.
        int[] required = {4, 7, 8, 15, 16, 17, 31, 32, 47, 48, 49, 64, 100, 255, 1_048_576};
        for (int length : required) {
            boolean found = false;
            for (WyhashVectors.Vector vector : WyhashVectors.CASES) {
                found |= vector.isPattern() && vector.patternLength() == length;
            }
            assertTrue(found, "the table must pin the pattern case of length " + length);
        }
    }

    @Test
    void theStreamingFormEqualsOneShotForTheLargeCases() {
        for (WyhashVectors.Vector vector : WyhashVectors.CASES) {
            if (!vector.isPattern() || vector.patternLength() < 1_000) {
                continue;
            }
            byte[] bytes = vector.bytes();
            Wyhash64.Streaming streaming = new Wyhash64.Streaming(vector.seed());
            streaming.update(bytes, 0, bytes.length / 2);
            streaming.update(bytes, bytes.length / 2, bytes.length - bytes.length / 2);
            assertEquals(vector.expected(), Wyhash64.hex(streaming.finalHash()),
                    "streaming '" + vector.label() + "' in two parts");
        }
    }

    @Test
    void theTextCasesAreTheirUtf8Bytes() {
        // The generated table stores a text case as hex; the port hashes those bytes. This is the assertion
        // that says so out loud, because Java's `hash(seed, String)` hashes the string's internal encoding and
        // would disagree with the reference for non-ASCII text.
        WyhashVectors.Vector utf8 = null;
        for (WyhashVectors.Vector vector : WyhashVectors.CASES) {
            if (vector.label().startsWith("utf8")) {
                utf8 = vector;
            }
        }
        assertTrue(utf8 != null, "the reference's utf8 fixture must be in the table");
        byte[] bytes = utf8.bytes();
        assertEquals(utf8.expected(), Wyhash64.hex(Wyhash64.hash(utf8.seed(), bytes)));
        assertEquals(7, bytes.length, "the fixture is the UTF-8 encoding of 'héllo\\n'");
        assertEquals("h\u00e9llo\n", new String(bytes, java.nio.charset.StandardCharsets.UTF_8));
    }

    @Test
    void aSegmentHashesTheWholeTableTheSameWayAsAByteArray() {
        for (WyhashVectors.Vector vector : WyhashVectors.CASES) {
            byte[] bytes = vector.bytes();
            assertEquals(Wyhash64.hex(Wyhash64.hash(vector.seed(), bytes)),
                    Wyhash64.hex(Wyhash64.hash(vector.seed(), MemorySegment.ofArray(bytes))),
                    "segment path for '" + vector.label() + "'");
        }
    }

    @Test
    void theHexFormIsSixteenLowercaseCharacters() {
        assertEquals("0409638ee2bde459", Wyhash64.hex(Wyhash64.hash(0, new byte[0])));
        assertEquals(Wyhash64.hex(-1L), HexFormat.of().toHexDigits(-1L).toLowerCase());
        assertEquals("ffffffffffffffff", Wyhash64.hex(-1L));
    }
}