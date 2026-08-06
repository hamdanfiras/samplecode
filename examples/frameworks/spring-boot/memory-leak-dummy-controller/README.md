# Spring Boot 3 Memory Leak Dummy Controller

Small Spring Boot 3 application with a `DummyController` that intentionally retains memory so tools such as Java Flight Recorder, Java Mission Control, and VisualVM have leaks to inspect.

This is intentionally unsafe test code. Do not run it in a shared or production environment.

## Run

```bash
mvn spring-boot:run
```

For JFR-friendly testing:

```bash
mvn spring-boot:run -Dspring-boot.run.jvmArguments="-XX:StartFlightRecording=filename=dummy-leak.jfr,dumponexit=true,settings=profile"
```

The service starts on port `8080` by default.

## Endpoints

```bash
# Show retained heap/direct/thread leak state and JVM memory
curl http://localhost:8080/dummy/status

# Retain heap byte arrays. Default is 10 MB, capped at 256 MB per request.
curl "http://localhost:8080/dummy/leak/heap?mb=50"

# Retain direct byte buffers. Default is 10 MB, capped at 256 MB per request.
curl "http://localhost:8080/dummy/leak/direct?mb=50"

# Retain many map entries with duplicated string payloads.
curl "http://localhost:8080/dummy/leak/strings?entries=10000&valueSize=2048"

# Start sleeping threads that retain per-thread heap payloads.
curl "http://localhost:8080/dummy/leak/threads?count=5&payloadMb=5"

# Release retained references and interrupt dummy threads.
curl -X POST http://localhost:8080/dummy/reset
```

## Suggested Observation Flow

1. Start the app with JFR enabled.
2. Open VisualVM or JDK Mission Control and attach to the process.
3. Call one or more `/dummy/leak/*` endpoints repeatedly.
4. Watch heap usage, direct memory, allocation hotspots, retained objects, and thread count.
5. Trigger heap dumps before and after `/dummy/reset` to compare retained references.

