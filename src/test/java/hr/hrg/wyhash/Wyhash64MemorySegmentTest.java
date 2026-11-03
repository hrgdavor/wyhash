// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Davor Hrg
package hr.hrg.wyhash;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

import java.io.IOException;
import java.lang.foreign.Arena;
import java.lang.foreign.MemorySegment;
import java.lang.foreign.ValueLayout;
import java.nio.channels.FileChannel;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.util.Random;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

/**
 * The {@link MemorySegment} path: hashing bytes that live outside the Java heap without copying them.
 *
 * <p>The contract is not "a hash of a segment" — it is that a segment is <em>the same bytes</em>. So every test
 * here compares the segment result against the {@code byte[]} result for the same content, at the lengths that
 * choose the algorithm's branches and at offsets that are deliberately unaligned, and the 1 MiB case is
 * compared against the value in {@code conformance/wyhash-vectors.json} so the new path is tied to the
 * reference and not only to the other Java paths.</p>
 *
 * <p>Memory-mapped files get their own test because that is the use case the path exists for: a caller that
 * mapped a file, or holds an arena allocation, should not have to copy it into a {@code byte[]} to hash it.</p>
 */
class Wyhash64MemorySegmentTest {

    /** The lengths that walk the algorithm's branches, plus the ones the vector file uses. */
    private static final int[] LENGTHS = {
            0, 1, 2, 3, 4, 5, 7, 8, 9, 15, 16, 17, 23, 24, 25, 31, 32, 33, 47, 48, 49, 50, 63, 64, 65, 100, 255,
            256, 1000, 10_800,
    };

    private static byte[] pattern(int length) {
        byte[] bytes = new byte[length];
        for (int i = 0; i < length; i++) {
            bytes[i] = (byte) ((i * 7 + 3) & 0xFF);
        }
        return bytes;
    }

    @Test
    void aHeapSegmentHashesLikeTheSameByteArray() {
        for (int length : LENGTHS) {
            byte[] bytes = pattern(length);
            assertEquals(Wyhash64.hash(0, bytes), Wyhash64.hash(0, MemorySegment.ofArray(bytes)),
                    "length " + length);
        }
    }

    @Test
    void aNativeSegmentHashesLikeTheSameByteArray() {
        for (int length : LENGTHS) {
            byte[] bytes = pattern(length);
            try (Arena arena = Arena.ofConfined()) {
                MemorySegment segment = arena.allocate(length == 0 ? 1 : length);
                if (length > 0) {
                    MemorySegment.copy(bytes, 0, segment, ValueLayout.JAVA_BYTE, 0, length);
                }
                assertEquals(Wyhash64.hash(0, bytes), Wyhash64.hash(0, segment.reinterpret(length)),
                        "length " + length);
            }
        }
    }

    @Test
    void aSliceHashesLikeTheSameSliceOfAByteArray() {
        byte[] bytes = pattern(300);
        for (int off : new int[] {0, 1, 3, 4, 7, 8, 24, 48, 49, 100}) {
            for (int length : new int[] {0, 1, 3, 4, 16, 17, 48, 49, 64, 100}) {
                if (off + length > bytes.length) {
                    continue;
                }
                assertEquals(Wyhash64.hash(0, bytes, off, length),
                        Wyhash64.hash(0, MemorySegment.ofArray(bytes), off, length),
                        "off " + off + ", length " + length);
            }
        }
    }

    @Test
    void anEmptySegmentHashesLikeNoBytesAtAll() {
        assertEquals(Wyhash64.hash(0, new byte[0]), Wyhash64.hash(0, MemorySegment.ofArray(new byte[0])));
        assertEquals("0409638ee2bde459", String.format("%016x", Wyhash64.hash(0, MemorySegment.NULL.reinterpret(0))));
    }

    @Test
    void aSeededSegmentHashHonoursTheSeed() {
        byte[] bytes = pattern(64);
        assertEquals(Wyhash64.hash(1, bytes), Wyhash64.hash(1, MemorySegment.ofArray(bytes)));
        assertEquals(Wyhash64.hash(0x9E3779B97F4A7C15L, bytes),
                Wyhash64.hash(0x9E3779B97F4A7C15L, MemorySegment.ofArray(bytes)));
    }

    @Test
    void theOneMebibyteReferenceCaseHashesTheSameThroughASegment() {
        // The value is `pattern-1048576` in conformance/wyhash-vectors.json: a native segment must produce it,
        // which ties this path to the reference rather than only to the other Java paths.
        int length = 1_048_576;
        byte[] bytes = pattern(length);
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment segment = arena.allocate(length);
            MemorySegment.copy(bytes, 0, segment, ValueLayout.JAVA_BYTE, 0, length);
            assertEquals("4f0cfe3df890f19a", String.format("%016x", Wyhash64.hash(0, segment)));
        }
    }

    @Test
    void aMemoryMappedFileHashesLikeItsBytes(@TempDir Path directory) throws IOException {
        byte[] bytes = pattern(5_000);
        Path file = directory.resolve("pattern.bin");
        Files.write(file, bytes);

        try (Arena arena = Arena.ofConfined(); FileChannel channel = FileChannel.open(file, StandardOpenOption.READ)) {
            // The FFM mapping overload — `map(mode, offset, size, arena)`. The three-argument one returns the
            // older `MappedByteBuffer`, which is not a `MemorySegment`.
            MemorySegment mapped = channel.map(FileChannel.MapMode.READ_ONLY, 0, bytes.length, arena);
            assertEquals(Wyhash64.hash(0, bytes), Wyhash64.hash(0, mapped));
            // A window into the mapping, unaligned, is the same bytes as the same window of the array.
            assertEquals(Wyhash64.hash(0, bytes, 1000, 3000), Wyhash64.hash(0, mapped, 1000, 3000));
        }
    }

    @Test
    void streamingFromSegmentsInAnyChunkingEqualsOneShot() {
        byte[] bytes = pattern(5_000);
        MemorySegment segment = MemorySegment.ofArray(bytes);
        long oneShot = Wyhash64.hash(0, bytes);

        Wyhash64.Streaming whole = new Wyhash64.Streaming(0);
        whole.update(segment);
        assertEquals(oneShot, whole.finalHash(), "one whole-segment update");

        // Splits that land inside a block, on a block boundary, and in the cached 16-byte tail window.
        for (int chunk : new int[] {1, 7, 16, 17, 23, 24, 25, 47, 48, 49, 96, 1000}) {
            Wyhash64.Streaming streaming = new Wyhash64.Streaming(0);
            for (long at = 0; at < bytes.length; at += chunk) {
                long length = Math.min(chunk, bytes.length - at);
                streaming.update(segment, at, length);
            }
            assertEquals(oneShot, streaming.finalHash(), "chunk " + chunk);
        }

        // Random splits, and a mix of segment, byte[] and single-byte updates: the streaming form must not
        // care how the caller got the bytes there.
        Random random = new Random(42);
        Wyhash64.Streaming mixed = new Wyhash64.Streaming(0);
        int at = 0;
        while (at < bytes.length) {
            int length = Math.min(1 + random.nextInt(200), bytes.length - at);
            switch (random.nextInt(3)) {
                case 0 -> mixed.update(segment, at, length);
                case 1 -> mixed.update(bytes, at, length);
                default -> {
                    for (int i = 0; i < length; i++) {
                        mixed.updateByte(bytes[at + i]);
                    }
                }
            }
            at += length;
        }
        assertEquals(oneShot, mixed.finalHash(), "mixed segment/byte[]/updateByte");
    }

    @Test
    void streamingSegmentsAcrossTheSixteenByteTailWindowEqualsOneShot() {
        // The interesting region is where the pending tail is shorter than 16 bytes and the 16-byte final
        // window spans the last full block and the tail. Exercise every split point around it.
        for (int length = 48; length < 120; length++) {
            byte[] bytes = pattern(length);
            MemorySegment segment = MemorySegment.ofArray(bytes);
            long oneShot = Wyhash64.hash(0, bytes);
            for (int split = 0; split <= length; split++) {
                Wyhash64.Streaming streaming = new Wyhash64.Streaming(0);
                streaming.update(segment, 0, split);
                streaming.update(segment, split, length - split);
                assertEquals(oneShot, streaming.finalHash(), "length " + length + ", split " + split);
            }
        }
    }

    @Test
    void aRegionBeyondTheSegmentIsReportedByTheFfmApi() {
        MemorySegment segment = MemorySegment.ofArray(pattern(16));
        assertThrows(IndexOutOfBoundsException.class, () -> Wyhash64.hash(0, segment, 0, 17));
        assertThrows(IndexOutOfBoundsException.class, () -> Wyhash64.hash(0, segment, 8, 16));
    }
}