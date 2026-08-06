package com.example.dummy;

import java.lang.management.ManagementFactory;
import java.lang.management.MemoryMXBean;
import java.lang.management.MemoryUsage;
import java.nio.ByteBuffer;
import java.time.Instant;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/dummy")
public class DummyController {

    private static final int ONE_MB = 1024 * 1024;
    private static final int MAX_MB_PER_REQUEST = 256;
    private static final int MAX_STRING_ENTRIES_PER_REQUEST = 250_000;
    private static final int MAX_STRING_VALUE_SIZE = 64 * 1024;
    private static final int MAX_THREADS_PER_REQUEST = 50;

    private static final List<byte[]> HEAP_LEAK = new CopyOnWriteArrayList<>();
    private static final List<ByteBuffer> DIRECT_LEAK = new CopyOnWriteArrayList<>();
    private static final Map<String, String> STRING_LEAK = new ConcurrentHashMap<>();
    private static final List<Thread> THREAD_LEAK = new CopyOnWriteArrayList<>();

    private static final AtomicLong HEAP_BYTES_RETAINED = new AtomicLong();
    private static final AtomicLong DIRECT_BYTES_RETAINED = new AtomicLong();
    private static final AtomicLong STRING_VALUES_RETAINED = new AtomicLong();
    private static final AtomicInteger THREAD_COUNTER = new AtomicInteger();

    @GetMapping("/status")
    public Map<String, Object> status() {
        MemoryMXBean memory = ManagementFactory.getMemoryMXBean();
        Runtime runtime = Runtime.getRuntime();

        Map<String, Object> response = new LinkedHashMap<>();
        response.put("time", Instant.now().toString());
        response.put("heapLeak", Map.of(
                "chunks", HEAP_LEAK.size(),
                "retainedBytes", HEAP_BYTES_RETAINED.get(),
                "retainedMegabytes", toMegabytes(HEAP_BYTES_RETAINED.get())));
        response.put("directLeak", Map.of(
                "buffers", DIRECT_LEAK.size(),
                "retainedBytes", DIRECT_BYTES_RETAINED.get(),
                "retainedMegabytes", toMegabytes(DIRECT_BYTES_RETAINED.get())));
        response.put("stringLeak", Map.of(
                "entries", STRING_LEAK.size(),
                "approxValueBytes", STRING_VALUES_RETAINED.get(),
                "approxValueMegabytes", toMegabytes(STRING_VALUES_RETAINED.get())));
        response.put("threadLeak", Map.of(
                "threads", THREAD_LEAK.size(),
                "aliveThreads", THREAD_LEAK.stream().filter(Thread::isAlive).count()));
        response.put("jvm", Map.of(
                "heap", memoryUsage(memory.getHeapMemoryUsage()),
                "nonHeap", memoryUsage(memory.getNonHeapMemoryUsage()),
                "runtime", Map.of(
                        "totalMemoryBytes", runtime.totalMemory(),
                        "freeMemoryBytes", runtime.freeMemory(),
                        "maxMemoryBytes", runtime.maxMemory())));

        return response;
    }

    @GetMapping("/leak/heap")
    public Map<String, Object> leakHeap(@RequestParam(defaultValue = "10") int mb) {
        int safeMb = clamp(mb, 1, MAX_MB_PER_REQUEST);
        byte[] retained = new byte[safeMb * ONE_MB];

        for (int i = 0; i < retained.length; i += 4096) {
            retained[i] = 1;
        }

        HEAP_LEAK.add(retained);
        long retainedBytes = HEAP_BYTES_RETAINED.addAndGet(retained.length);

        return Map.of(
                "type", "heap",
                "addedMegabytes", safeMb,
                "totalRetainedMegabytes", toMegabytes(retainedBytes),
                "chunks", HEAP_LEAK.size());
    }

    @GetMapping("/leak/direct")
    public Map<String, Object> leakDirect(@RequestParam(defaultValue = "10") int mb) {
        int safeMb = clamp(mb, 1, MAX_MB_PER_REQUEST);
        ByteBuffer retained = ByteBuffer.allocateDirect(safeMb * ONE_MB);

        for (int i = 0; i < retained.capacity(); i += 4096) {
            retained.put(i, (byte) 1);
        }

        DIRECT_LEAK.add(retained);
        long retainedBytes = DIRECT_BYTES_RETAINED.addAndGet(retained.capacity());

        return Map.of(
                "type", "direct",
                "addedMegabytes", safeMb,
                "totalRetainedMegabytes", toMegabytes(retainedBytes),
                "buffers", DIRECT_LEAK.size());
    }

    @GetMapping("/leak/strings")
    public Map<String, Object> leakStrings(
            @RequestParam(defaultValue = "10000") int entries,
            @RequestParam(defaultValue = "1024") int valueSize) {
        int safeEntries = clamp(entries, 1, MAX_STRING_ENTRIES_PER_REQUEST);
        int safeValueSize = clamp(valueSize, 1, MAX_STRING_VALUE_SIZE);
        String payload = "x".repeat(safeValueSize);

        for (int i = 0; i < safeEntries; i++) {
            String uniqueKey = UUID.randomUUID().toString();
            STRING_LEAK.put(uniqueKey, uniqueKey + ":" + payload);
        }

        long approxBytes = (long) safeEntries * (safeValueSize + 37);
        long retainedBytes = STRING_VALUES_RETAINED.addAndGet(approxBytes);

        return Map.of(
                "type", "strings",
                "addedEntries", safeEntries,
                "valueSizeBytes", safeValueSize,
                "totalEntries", STRING_LEAK.size(),
                "approxRetainedMegabytes", toMegabytes(retainedBytes));
    }

    @GetMapping("/leak/threads")
    public Map<String, Object> leakThreads(
            @RequestParam(defaultValue = "1") int count,
            @RequestParam(defaultValue = "1") int payloadMb) {
        int safeCount = clamp(count, 1, MAX_THREADS_PER_REQUEST);
        int safePayloadMb = clamp(payloadMb, 1, MAX_MB_PER_REQUEST);
        List<String> names = new ArrayList<>();

        for (int i = 0; i < safeCount; i++) {
            byte[] retainedByThread = new byte[safePayloadMb * ONE_MB];
            retainedByThread[0] = 1;

            Thread thread = new Thread(() -> sleepForever(retainedByThread),
                    "dummy-leak-thread-" + THREAD_COUNTER.incrementAndGet());
            thread.start();

            THREAD_LEAK.add(thread);
            HEAP_BYTES_RETAINED.addAndGet(retainedByThread.length);
            names.add(thread.getName());
        }

        return Map.of(
                "type", "threads",
                "addedThreads", safeCount,
                "payloadMegabytesPerThread", safePayloadMb,
                "totalThreads", THREAD_LEAK.size(),
                "threadNames", names);
    }

    @PostMapping("/reset")
    public ResponseEntity<Map<String, Object>> reset() {
        int interruptedThreads = 0;
        for (Thread thread : THREAD_LEAK) {
            if (thread.isAlive()) {
                thread.interrupt();
                interruptedThreads++;
            }
        }

        HEAP_LEAK.clear();
        DIRECT_LEAK.clear();
        STRING_LEAK.clear();
        THREAD_LEAK.clear();
        HEAP_BYTES_RETAINED.set(0);
        DIRECT_BYTES_RETAINED.set(0);
        STRING_VALUES_RETAINED.set(0);

        System.gc();

        return ResponseEntity.ok(Map.of(
                "reset", true,
                "interruptedThreads", interruptedThreads));
    }

    private static void sleepForever(byte[] retainedPayload) {
        try {
            while (!Thread.currentThread().isInterrupted()) {
                retainedPayload[0]++;
                Thread.sleep(60_000);
            }
        } catch (InterruptedException ignored) {
            Thread.currentThread().interrupt();
        }
    }

    private static Map<String, Long> memoryUsage(MemoryUsage usage) {
        return Map.of(
                "initBytes", usage.getInit(),
                "usedBytes", usage.getUsed(),
                "committedBytes", usage.getCommitted(),
                "maxBytes", usage.getMax());
    }

    private static int clamp(int value, int min, int max) {
        return Math.max(min, Math.min(max, value));
    }

    private static long toMegabytes(long bytes) {
        return bytes / ONE_MB;
    }
}

