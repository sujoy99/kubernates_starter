# Phase 2 — Dockerize it

## What we built

A multi-stage `app/Dockerfile` that packages the Phase 1 Spring Boot app into a Docker image
(`hello-service:0.1.0`), an `app/.dockerignore` to keep the build context clean, and a smoke-test
script (`scripts/smoke-docker.sh`) that builds the image, runs it, and proves the endpoints answer
before declaring success.

## Why

Kubernetes doesn't run Java apps — it runs **containers**. Before we can hand anything to `kind` or a
real cluster (Phase 3+), the app needs to exist as a self-contained image: code + JRE + everything it
needs, with nothing assumed about the host machine. This is the "sealed meal-kit box" from the
[ROADMAP's mental model](../ROADMAP.md#1-the-30-second-mental-model) — Docker packages the app once, and
that exact package is what every later phase runs, unmodified.

## New concepts introduced

- **Image** — the packaged, immutable "recipe + ingredients" (our app's `.jar` + a JRE + OS libraries).
  Built once, run many times. `hello-service:0.1.0` is an image.
- **Container** — a *running instance* of an image, like a process. You can start many containers from
  one image; each is isolated but starts from the exact same bytes.
- **Multi-stage build** — a `Dockerfile` with more than one `FROM`. Our stage 1 (`maven:3.9-eclipse-temurin-21`)
  has the full JDK, Maven, and every downloaded dependency needed to *compile* the app — none of that
  belongs in the shipped image. Stage 2 (`eclipse-temurin:21-jre-alpine`) starts fresh from a minimal
  JRE-only base and copies in only the finished `.jar` from stage 1 with `COPY --from=build`. The result:
  a final image (~94 MB content size) instead of shipping the ~500MB+ build toolchain, and a smaller
  attack surface since there's no compiler or build tool inside the thing you actually run.
- **Image tag/version** — the `:0.1.0` in `hello-service:0.1.0`. Images are named + tagged so you can
  have multiple versions around and refer to exactly one (this matters a lot once Phase 7 does rolling
  updates between versions).
- **Non-root container user** — by default a container runs as `root` inside its own namespace, which is
  more privilege than the app needs and a bigger blast radius if it's ever compromised. Our Dockerfile
  creates an unprivileged `spring` user (`addgroup -S spring && adduser -S spring -G spring`) and switches
  to it with `USER spring` before the app ever starts.
- **Smoke test** — a fast, shallow test that just proves "the thing starts and responds," as opposed to
  testing business logic (that's what Phase 1's `mvn test` already covers). `scripts/smoke-docker.sh`
  builds the image, runs a container, and polls `/actuator/health` until it reports `UP` (or times out
  and fails loudly) — the same endpoint Kubernetes will poll for liveness/readiness starting Phase 4.

## Step-by-step reproduction

```bash
# Build the image (multi-stage build compiles the jar, then discards the build tools)
docker build -t hello-service:0.1.0 ./app

# Run it, mapping container port 8080 to your laptop's port 8080
docker run -d --name hello-service -p 8080:8080 hello-service:0.1.0

# Hit both endpoints
curl http://localhost:8080/api/hello
# {"service":"hello-service","message":"Hello from Kubernetes!"}
curl http://localhost:8080/actuator/health
# {"status":"UP"}

# Confirm it's not running as root
docker exec hello-service whoami
# spring

# Clean up
docker rm -f hello-service
```

Or just run the whole gate in one command:

```bash
./scripts/smoke-docker.sh
```

## How we tested it

**Automated (the Phase 2 gate):**

```bash
./scripts/smoke-docker.sh
```
```
==> Building image hello-service:0.1.0
...
==> Starting container
==> Polling http://localhost:8080/actuator/health (timeout: 30s)
==> Healthy after 2s. Verifying /api/hello
PASSED
{"service":"hello-service","message":"Hello from Kubernetes!"}
```

**Manual:** ran `docker build` + `docker run` directly, `curl`'d both endpoints and confirmed the same
JSON as Phase 1's local run, and confirmed `docker exec hello-service whoami` prints `spring`, not
`root`.

## Common errors & fixes

- **Build context includes `target/`, bloating/slowing the build.** Fixed with `app/.dockerignore`
  (excludes `target/`, IDE files, `.git/`). Without it, Docker copies your local Maven build output into
  the image context for no reason — wasted time and a larger, less reproducible build.
- **Forgetting to remove a previous container before re-running with the same `--name`** produces
  `docker: Error response from daemon: Conflict. The container name "/hello-service" is already in use`.
  Fix: `docker rm -f hello-service` first (the smoke-test script does this automatically before and
  after each run).
- **Tests aren't re-run inside the Docker build.** We pass `-DskipTests` to `mvn package` in the
  Dockerfile intentionally — `mvn test` is Phase 1's gate and already runs before you'd ever build an
  image; re-running it here would just slow down every image build for no new signal. If that ever
  stops being true (e.g. once CI in Phase 10 builds images from a fresh checkout with no prior test run),
  revisit this.
