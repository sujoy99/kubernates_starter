# Phase 1 — The Spring Boot microservice (no Docker yet)

## What we built

A minimal Spring Boot 3 app (`app/`) with one REST endpoint (`GET /api/hello`) that returns a JSON
greeting, plus a health-check endpoint (`GET /actuator/health`) provided for free by Spring Actuator.
The greeting text and service name are read from `application.yml`, not hardcoded.

## Why

Before we wrap anything in Docker or Kubernetes, we need a real, working, *testable* piece of software.
Everything after this phase — the container, the Pods, the Service, the Ingress — exists only to run
and expose this app reliably. If the app itself is untested or its config is hardcoded, every later
phase inherits that weakness. So Phase 1 sets two habits early: **write tests as you go**, and
**externalize configuration from day one** (see "12-factor app" principles) — because in Phase 5 we'll
change this exact config from Kubernetes without touching code.

## New concepts introduced

- **REST endpoint** — a URL that responds to HTTP requests (here, `GET`) with data, usually JSON.
  `@RestController` + `@GetMapping` in Spring Boot wire a URL path to a Java method.
- **Spring Actuator** — a Spring Boot library that adds ready-made operational endpoints
  (`/actuator/health`, `/actuator/info`, metrics, etc.) with almost no code. `/actuator/health` becomes
  the target Kubernetes polls in Phase 4 to know if the Pod is alive/ready.
- **Externalized configuration** — values like `app.greeting.message` live in `application.yml`, read
  into Java via `@Value("${...}")`, instead of being hardcoded in a Java file. This is what lets us
  change behavior later via a Kubernetes ConfigMap without rebuilding the app.
- **Unit test vs. integration test** — a *unit test* (`GreetingServiceTest`) checks one class in
  isolation, instantiated directly with `new`, no Spring involved — fast. An *integration test*
  (`HelloControllerTest`, using `@SpringBootTest` + `MockMvc`) boots the real Spring application context
  and simulates an HTTP request against it — slower but proves the wiring (controller → service →
  config) actually works end to end.

## Step-by-step reproduction

Prerequisite: JDK 21 (Spring Boot 3.x requires Java 17+). If your machine only has an older JDK
installed, install JDK 21 (e.g. via `winget install --id EclipseAdoptium.Temurin.21.JDK -e`) and point
`JAVA_HOME` at it for this project — no need to change your system default.

```bash
cd app

# Point this shell session's tools at JDK 21
export JAVA_HOME="/c/Program Files/Eclipse Adoptium/jdk-21.0.11.10-hotspot"
export PATH="$JAVA_HOME/bin:$PATH"

# Run the tests
mvn test

# Run the app
mvn spring-boot:run
```

In another terminal, once you see "Started HelloServiceApplication" in the logs:

```bash
curl http://localhost:8080/api/hello
# {"service":"hello-service","message":"Hello from Kubernetes!"}

curl http://localhost:8080/actuator/health
# {"status":"UP"}
```

Stop the app with `Ctrl+C` (or, if it's running in the background, find its PID and `kill` it).

## How we tested it

**Automated:**

```bash
mvn test
```
```
[INFO] Running com.example.helloservice.service.GreetingServiceTest
[INFO] Tests run: 1, Failures: 0, Errors: 0, Skipped: 0
[INFO] Running com.example.helloservice.web.HelloControllerTest
[INFO] Tests run: 1, Failures: 0, Errors: 0, Skipped: 0
[INFO] Tests run: 2, Failures: 0, Errors: 0, Skipped: 0
[INFO] BUILD SUCCESS
```

- `GreetingServiceTest` — a plain unit test asserting `GreetingService` returns exactly the app name and
  message it was constructed with.
- `HelloControllerTest` — boots the full Spring context and asserts `GET /api/hello` returns HTTP 200
  with the expected `service` and `message` JSON fields.

**Manual:** started the app with `mvn spring-boot:run`, then `curl`'d both endpoints and confirmed the
JSON responses shown above.

## Common errors & fixes

- **`java.lang.UnsupportedClassVersionError` or a Maven "requires Java 17" error.** Spring Boot 3.x
  needs Java 17+; this project targets Java 21. Check `java -version` — if it's older, install JDK 21
  and set `JAVA_HOME` before running Maven (see reproduction steps above). Multiple JDKs can coexist on
  one machine; you only need to point *this project's* shell session at the right one.
- **First `mvn test` or `mvn spring-boot:run` seems to hang.** It isn't hung — Maven is downloading
  Spring Boot's dependencies from Maven Central for the first time (can take a few minutes on a slow
  connection). Subsequent runs are fast because everything is cached locally (`~/.m2` or your configured
  local repo).
- **A backgrounded `mvn spring-boot:run` "finishes" immediately in your terminal/tooling but the app is
  still running.** If you launch it with `nohup ... &`, the *shell command* returns right away (that's
  what `&` does), while the actual Java process keeps running detached. Check with `ps aux | grep java`
  before assuming it died, and `kill <pid>` when you're done with it.
