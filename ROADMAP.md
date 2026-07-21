# Spring Boot on Kubernetes — Project Roadmap & Guide

> **Who this is for:** You (and future-you) — someone new to Kubernetes who wants to build a
> **production-grade** Dockerized Spring Boot microservice orchestrated by Kubernetes.
> Every section explains *what* we do, *why* we do it, and *what each piece means*.
>
> **Golden rule of this repo:** we never add a tool or a config line without explaining it.
> If you ever read something here you don't understand, that's a bug in this document — fix it.

---

## 1. The 30-second mental model

Think of it like a restaurant:

| Restaurant thing | Our tech thing | What it does |
|---|---|---|
| The recipe | **Spring Boot app (`.jar`)** | Your actual business logic / code |
| A sealed meal-kit box | **Docker image** | Your app + everything it needs to run, frozen into one shippable unit |
| A single cook following the recipe | **Container** | A *running* copy of the Docker image |
| The head chef assigning cooks, replacing sick ones, handling rush hour | **Kubernetes** | Runs many containers, restarts crashed ones, scales up under load |
| The restaurant building | **Node** (a VM/server) | The machine Kubernetes runs your containers on |
| The whole restaurant chain | **Cluster** | All the nodes managed together by Kubernetes |

**The one sentence to remember:** *Docker packages the app; Kubernetes runs and babysits many copies of that package.*

---

## 2. Vocabulary you'll actually need (Kubernetes edition)

You do **not** need all of Kubernetes. You need these ~8 concepts. We'll introduce each in the phase where it first appears — this is your glossary.

- **Pod** — the smallest thing Kubernetes runs. Usually = 1 container (your app). Think "one running instance."
- **Deployment** — a manager that says *"always keep N healthy Pods of this app running."* If a Pod dies, it makes a new one.
- **ReplicaSet** — the thing a Deployment uses under the hood to keep the Pod count correct. You rarely touch it directly.
- **Service** — a stable internal address + load balancer for your Pods. Pods come and go (new IPs each time); a Service gives them one unchanging name so other things can reliably reach them.
- **Ingress** — the front door. Routes outside HTTP traffic (e.g. `myapp.local/api`) to the right Service inside the cluster.
- **ConfigMap** — non-secret configuration (feature flags, URLs, log levels) kept *outside* your image so you don't rebuild to change a setting.
- **Secret** — like a ConfigMap but for sensitive values (passwords, API keys). Base64-encoded and handled more carefully.
- **Namespace** — a folder/room to group and isolate resources (e.g. `dev`, `staging`, `prod`).
- **Liveness / Readiness probe** — health checks. *Readiness* = "can I receive traffic yet?" *Liveness* = "am I still alive or should I be restarted?"

Keep this list nearby. Everything below is just these blocks assembled.

---

## 3. Architecture (the target we're building toward)

```
                    ┌─────────────────────────────────────────────┐
   Browser / curl   │                Kubernetes Cluster            │
        │           │                                             │
        ▼           │   ┌──────────┐      ┌─────────────────────┐ │
   ┌─────────┐      │   │ Ingress  │─────▶│  Service (ClusterIP)│ │
   │ Ingress │──────┼──▶│Controller│      └──────────┬──────────┘ │
   │  (URL)  │      │   └──────────┘                 │            │
   └─────────┘      │                     ┌──────────┼──────────┐ │
                    │                     ▼          ▼          ▼ │
                    │                 ┌──────┐   ┌──────┐   ┌──────┐
                    │                 │ Pod  │   │ Pod  │   │ Pod  │  ◀── Deployment keeps
                    │                 │(app) │   │(app) │   │(app) │      these N healthy
                    │                 └──────┘   └──────┘   └──────┘
                    │                     ▲          ▲          ▲     │
                    │            ConfigMap + Secret injected here     │
                    └─────────────────────────────────────────────┘
```

**Read it as:** traffic enters through the **Ingress**, hits a **Service** (the stable load-balancer),
which spreads it across several identical **Pods**. A **Deployment** guarantees the Pods stay alive.
**ConfigMap/Secret** feed configuration in without rebuilding the image.

---

## 4. Technology choices (and *why* each one)

These are the defaults this repo commits to. Each has a beginner-friendly reason. You can swap any of them later.

| Layer | Choice | Why this one (beginner reasoning) |
|---|---|---|
| Language/Framework | **Java 21 + Spring Boot 3.x** | LTS Java; Spring Boot is the industry-standard way to build Java microservices. Built-in health checks & metrics via Actuator. |
| Build tool | **Maven** | Most common, tons of tutorials. (Gradle is fine too; Maven is friendlier for beginners.) |
| Containerization | **Docker** (multi-stage build) | The standard. Multi-stage = small, secure final image. |
| Local Kubernetes | **kind** *or* **minikube** | Runs a real K8s cluster on your laptop. `kind` = "Kubernetes IN Docker", fast & light. Great for POC. |
| K8s CLI | **kubectl** | The remote control for talking to any cluster. |
| Manifests | **Plain YAML → later Helm** | Start with raw YAML so you learn the fundamentals; graduate to Helm for templating once it clicks. |
| Ingress | **NGINX Ingress Controller** | Most widely used, best-documented. |
| Observability | **Spring Actuator + Prometheus + Grafana** (later phase) | Actuator exposes health/metrics; Prometheus scrapes them; Grafana graphs them. |

> **Why "production-grade" for a POC?** Because bad habits are hard to unlearn. We'll do the *right*
> things (health probes, resource limits, non-root containers, externalized config) from day one, even
> though the app is tiny. Production-grade is a *mindset*, not a size.

---

## 5. Prerequisites — install these first

Install in this order. Verify each with the check command before moving on.

| Tool | What it's for | Verify command |
|---|---|---|
| **JDK 21** | Compile & run the Spring Boot app | `java -version` |
| **Maven** | Build the app | `mvn -version` |
| **Docker Desktop** | Build/run containers (also powers `kind`) | `docker --version` |
| **kubectl** | Talk to Kubernetes | `kubectl version --client` |
| **kind** | Local Kubernetes cluster | `kind --version` |
| **Helm** (later) | Package manager for K8s | `helm version` |
| **GitHub CLI (`gh`)** | Create/read issues, automate PRs from the terminal | `gh --version` |

> On Windows: Docker Desktop with the WSL2 backend is the smoothest path. `kubectl`, `kind`, `helm`,
> and `gh` are all installable via `winget` or `choco`. We'll cover exact commands in Phase 3.

---

## 6. Quality gates & testing strategy

**Every phase below is only considered "done" when it passes its gate.** A gate is a concrete,
checkable condition — never "looks right." This is what makes a POC "production-grade": the habit of
proving things work, not assuming they do.

### 6.1 The three gates every phase must clear

1. **Automated tests pass.** Whatever kind of test applies to that phase (see table below) must be
   green — run in your terminal and (from Phase 10 onward) in CI.
2. **Manual verification done.** A human (you) actually ran the milestone command and saw the real
   result — a curl response, a `kubectl get pods` showing `Running`, etc. Screenshots/output pasted
   into the phase's doc page count as evidence.
3. **Beginner-friendly docs written.** A new `docs/phase-N-<name>.md` page exists explaining what was
   built, why, and how to reproduce it from scratch — see Section 6.3.

A phase's GitHub Issue (Section 11) is only closed once all three boxes are checked.

### 6.2 What kind of test applies at each layer

| Layer | Test type | Tool | Example |
|---|---|---|---|
| Spring Boot business logic | **Unit test** | JUnit 5 + Mockito | Does the greeting service return the right string? |
| Spring Boot HTTP layer | **Slice/integration test** | `@SpringBootTest` + `MockMvc` | Does `GET /api/hello` return 200 + expected JSON? |
| Docker image | **Smoke test** | `docker run` + `curl` in a script | Does the container start and answer `/actuator/health` within N seconds? |
| Kubernetes manifests | **Static validation** | `kubectl apply --dry-run=client`, `kubeval`/`kube-score` (later) | Is the YAML syntactically & schematically valid before we ever apply it for real? |
| Running cluster state | **Smoke/E2E test** | a small bash/PowerShell script using `kubectl` + `curl` | After `kubectl apply -f k8s/`, do Pods reach `Ready` and does the Service answer? |
| Config changes | **Regression check** | manual + smoke script | After a ConfigMap edit + rollout restart, does the new value show up with zero code changes? |

We start simple (Phase 1 unit tests) and add test types only when the phase introduces the layer they
cover — you're never asked to write a test for something you haven't learned yet.

### 6.3 Documentation requirement (beginner-friendly, every phase)

Each phase adds one page to `docs/`, named `docs/phase-N-<short-name>.md`, containing:

1. **What we built** — one paragraph, plain language.
2. **Why** — the problem this phase solves (tie back to Section 1's mental model where possible).
3. **New concepts introduced** — short glossary entries, expanding on Section 2.
4. **Step-by-step reproduction** — the exact commands, in order, a total beginner can copy-paste.
5. **How we tested it** — the commands/output proving the gate passed (Section 6.1, point 1 & 2).
6. **Common errors & fixes** — anything that actually went wrong while building it, and the fix.

> Point 6 is the most valuable page in the whole repo over time — it's a running "gotchas" log written
> from real mistakes, not hypothetical ones.

---

## 7. The roadmap — phased plan

Each phase is a **working, demoable milestone**, tracked as its own **GitHub Issue** (see Section 11).
We do not skip ahead. Every phase's checklist now always ends with the same two gate items — **Tests**
and **Docs** — in addition to its build tasks. A phase isn't done until every box, including those two,
is checked.

### Phase 0 — Foundations & repo scaffolding  ✅ *(this document)*
- [x] Agree on architecture & tech choices (this file)
- [ ] Create the folder structure (see Section 8)
- [ ] Add `.gitignore`, `README.md`, and initialize git; push to remote
- [ ] Create GitHub Issues for Phases 0–10 (this phase's "test" is the repo scaffold existing and issues filed)
- [ ] **Docs:** `docs/phase-0-foundations.md`

**You'll learn:** how the project is organized and why, and how we track work going forward.

---

### Phase 1 — The Spring Boot microservice (no Docker yet)  ✅
- [x] Generate a minimal Spring Boot app (`web` + `actuator` dependencies)
- [x] One REST endpoint: `GET /api/hello` → returns a JSON greeting
- [x] Enable Actuator health endpoint: `GET /actuator/health`
- [x] Externalize config via `application.yml` (port, app name, a greeting message)
- [x] Run locally: `mvn spring-boot:run`, hit both endpoints in a browser
- [x] **Tests:** JUnit unit test for the greeting logic + `@SpringBootTest`/`MockMvc` test for `GET /api/hello`; `mvn test` green
- [x] **Docs:** `docs/phase-1-spring-boot-app.md`

**You'll learn:** what the app actually *does* before we wrap it in anything. **Milestone:** app runs on `http://localhost:8080`.

**New concepts introduced:** REST endpoint, Spring Actuator (the source of our future health probes), unit vs. integration test.

---

### Phase 2 — Dockerize it  ✅
- [x] Write a **multi-stage `Dockerfile`** (stage 1 builds the jar, stage 2 runs it on a slim JRE)
- [x] Run as a **non-root user** inside the container (security)
- [x] Add a `.dockerignore`
- [x] Build: `docker build -t hello-service:0.1.0 .`
- [x] Run: `docker run -p 8080:8080 hello-service:0.1.0` and confirm the endpoints work
- [x] **Tests:** smoke-test script (`docs`/`scripts`) that runs the container, polls `/actuator/health` until 200 OK or times out and fails loudly
- [x] **Docs:** `docs/phase-2-dockerize.md`

**You'll learn:** the difference between an image and a container; why multi-stage builds keep images
small and safe; why we never run as root. **Milestone:** the exact same app runs *inside a container*.

**New concepts introduced:** image, container, multi-stage build, image tag/version, smoke test.

---

### Phase 3 — A local Kubernetes cluster  ✅
- [x] Create a `kind` cluster: `kind create cluster --name poc`
- [x] Understand `kubectl get nodes` (you now have a 1-node cluster)
- [x] Load your local image into kind: `kind load docker-image hello-service:0.1.0 --name poc`
- [x] **Tests:** `kubectl get nodes` shows `Ready`; `kubectl cluster-info` succeeds
- [x] **Docs:** `docs/phase-3-local-cluster.md`

**You'll learn:** what a cluster/node is, and the crucial gotcha that a local cluster can't see your
local Docker images until you *load* them in. **Milestone:** `kubectl get nodes` shows a Ready node.

**New concepts introduced:** cluster, node, kubectl context.

---

### Phase 4 — First deployment to Kubernetes
- [ ] Write `k8s/deployment.yaml` — 2 replicas, resource requests/limits, liveness & readiness probes (wired to `/actuator/health`)
- [ ] Write `k8s/service.yaml` — a `ClusterIP` Service in front of the Pods
- [ ] Validate before applying: `kubectl apply -f k8s/ --dry-run=client`
- [ ] Apply: `kubectl apply -f k8s/`
- [ ] Inspect: `kubectl get pods`, `kubectl describe pod`, `kubectl logs`
- [ ] Reach it: `kubectl port-forward svc/hello-service 8080:80`
- [ ] **Tests:** E2E smoke script — apply manifests, wait for `Ready` Pods, `curl` through the port-forward, assert 200; also kill a Pod and assert it's replaced within N seconds
- [ ] **Docs:** `docs/phase-4-first-deployment.md`

**You'll learn:** the core K8s objects and the debugging trio (`get` / `describe` / `logs`) you'll use
forever. **Milestone:** your app runs as 2 self-healing Pods; kill one and watch K8s recreate it.

**New concepts introduced:** Pod, Deployment, ReplicaSet, Service, probes, resource requests/limits, dry-run validation.

---

### Phase 5 — Configuration & secrets, done right
- [ ] Move the greeting message + log level into a **ConfigMap**
- [ ] Add a dummy **Secret** (e.g. a fake API key) and inject it as an env var
- [ ] Confirm you can change config **without rebuilding the image** (edit ConfigMap → restart rollout)
- [ ] **Tests:** regression script — change the ConfigMap value, `kubectl rollout restart`, poll the endpoint until the new value appears, assert no image rebuild happened
- [ ] **Docs:** `docs/phase-5-config-and-secrets.md`

**You'll learn:** the 12-factor principle of externalized config; why secrets live outside the image.
**Milestone:** change a message with zero code changes and zero image rebuilds.

**New concepts introduced:** ConfigMap, Secret, `kubectl rollout restart`.

---

### Phase 6 — Ingress (a real front door)
- [ ] Install the NGINX Ingress Controller into kind
- [ ] Write `k8s/ingress.yaml` routing `hello.local` → the Service
- [ ] Map `hello.local` in your hosts file and hit it from the browser
- [ ] **Tests:** E2E script — `curl http://hello.local/api/hello` (no port-forward) returns 200
- [ ] **Docs:** `docs/phase-6-ingress.md`

**You'll learn:** how external URLs map to internal Services. **Milestone:** browse to `http://hello.local/api/hello`.

**New concepts introduced:** Ingress, Ingress Controller, host-based routing.

---

### Phase 7 — Production-grade hardening
- [ ] Add **Namespaces** (`dev`) and put everything in it
- [ ] Add a **HorizontalPodAutoscaler** (scale on CPU)
- [ ] Add a **rolling update** strategy + demonstrate a zero-downtime deploy (v0.1.0 → v0.2.0)
- [ ] Add `securityContext` (read-only root FS, drop capabilities, non-root)
- [ ] Add **liveness/readiness/startup** probes tuned properly
- [ ] **Tests:** zero-downtime script — hammer the endpoint with continuous requests in a loop while rolling out v0.2.0, assert zero failed requests
- [ ] **Docs:** `docs/phase-7-hardening.md`

**You'll learn:** how real deployments stay available during releases and under load.
**Milestone:** deploy a new version with zero dropped requests.

**New concepts introduced:** Namespace, HPA, rolling update, securityContext, startup probe.

---

### Phase 8 — Observability (see inside the box)
- [ ] Expose Prometheus metrics via Actuator (`micrometer-registry-prometheus`)
- [ ] Deploy Prometheus + Grafana (via Helm)
- [ ] Build one Grafana dashboard (request rate, latency, memory)
- [ ] **Tests:** assert `/actuator/prometheus` returns metrics; assert Prometheus target shows `UP`
- [ ] **Docs:** `docs/phase-8-observability.md`

**You'll learn:** how you *know* the system is healthy in production. **Milestone:** a live dashboard of your app.

**New concepts introduced:** metrics scraping, Prometheus, Grafana, Micrometer.

---

### Phase 9 — Packaging with Helm (optional but recommended)
- [ ] Convert the raw YAML into a **Helm chart** with a `values.yaml`
- [ ] Install/upgrade/rollback with `helm`
- [ ] **Tests:** `helm lint`, `helm template` renders valid YAML, `helm install --dry-run`
- [ ] **Docs:** `docs/phase-9-helm.md`

**You'll learn:** how teams template and version their K8s deploys instead of hand-editing YAML.

---

### Phase 10 — CI/CD (stretch goal)
- [ ] GitHub Actions: on push → `mvn test` → build jar → build image → push to a registry → deploy
- [ ] Wire the Phase 1–9 test scripts into the pipeline as required checks (no merge if red)
- [ ] (Optional) GitOps with Argo CD
- [ ] **Tests:** a green Actions run is itself the test gate — PRs can't merge on red
- [ ] **Docs:** `docs/phase-10-cicd.md`

**You'll learn:** how code changes reach the cluster automatically and safely, and how a real "test gate" blocks bad merges.

---

## 8. Planned folder structure

```
kubernates/
├── ROADMAP.md                 ← this file (the guide)
├── README.md                  ← quick-start & command cheat-sheet (added Phase 0)
├── .gitignore
│
├── app/                       ← the Spring Boot microservice
│   ├── src/main/java/...
│   ├── src/test/java/...      ← unit + integration tests (Phase 1+)
│   ├── src/main/resources/application.yml
│   ├── pom.xml
│   ├── Dockerfile             ← added Phase 2
│   └── .dockerignore
│
├── k8s/                       ← plain Kubernetes YAML (Phases 4–7)
│   ├── namespace.yaml
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── configmap.yaml
│   ├── secret.yaml
│   ├── ingress.yaml
│   └── hpa.yaml
│
├── helm/                      ← Helm chart (Phase 9)
│   └── hello-service/
│
├── scripts/                   ← smoke-test / E2E scripts referenced by each phase's gate
│   ├── smoke-docker.sh
│   ├── smoke-k8s.sh
│   └── zero-downtime-check.sh
│
└── docs/                      ← one beginner-friendly page per phase (Section 6.3) + cheat-sheets
    ├── phase-0-foundations.md
    ├── phase-1-spring-boot-app.md
    ├── ...
    └── kubectl-cheatsheet.md
```

> We keep app code and infra (`k8s/`) **separate** on purpose — a core production principle. Your app
> shouldn't know or care *how* it's deployed.

---

## 9. `kubectl` survival kit (bookmark this)

You'll live in these commands. Don't memorize — recognize.

```bash
kubectl get pods                    # list Pods and their status
kubectl get all                     # everything in the current namespace
kubectl describe pod <name>         # detailed state + recent events (your #1 debug tool)
kubectl logs <pod>                  # app logs
kubectl logs -f <pod>               # follow logs live (like tail -f)
kubectl apply -f <file-or-dir>      # create/update resources from YAML
kubectl delete -f <file-or-dir>     # remove them
kubectl port-forward svc/x 8080:80  # tunnel a Service to your laptop
kubectl rollout status deploy/x     # watch a deployment roll out
kubectl rollout restart deploy/x    # restart Pods (e.g. after a ConfigMap change)
kubectl get events --sort-by=.lastTimestamp   # what just happened & why
```

**Debugging flow when something's broken:** `get pods` (see status) → `describe pod` (see events) →
`logs` (see the app's own error). 90% of problems reveal themselves in those three.

---

## 10. Definition of Done (for the whole POC)

The POC is "done" when a newcomer can, from a clean laptop:
1. Read this ROADMAP and understand the plan.
2. Follow the README to build the image, spin up `kind`, and `kubectl apply -f k8s/`.
3. Browse to `http://hello.local/api/hello` and get a response.
4. Kill a Pod and watch Kubernetes heal it.
5. Change a config value with no rebuild.
6. Deploy a new version with zero downtime.
7. Run every phase's test/smoke script and see them all pass.
8. Read `docs/` and understand *why*, not just *how*, for every phase.

If all eight work and are understood, the POC has achieved its goal: **not a big app, but a solid,
correct, well-understood, well-tested template you can reuse for real services.**

---

## 11. How we'll work together (process)

- **One phase at a time.** We finish, verify, and understand a phase before starting the next.
- **Every file gets commented** with beginner-friendly explanations inline.
- **Every new command** is explained the first time it appears.
- **When you're stuck,** we use the Section 9 debugging flow, not guesswork.
- This document is **living** — we check off boxes and refine explanations as we go.

### Issue tracking (GitHub Issues is our source of truth for "what's next")

- Every phase (0–10) is filed as **one GitHub Issue** in this repo, labeled `phase-N`, containing that
  phase's checklist from Section 7 as the issue body.
- Additional labels: `type:feature` (build tasks), `type:test` (the test-gate item),
  `type:docs` (the docs-gate item) — applied per phase as relevant.
- **Before starting work, we read open issues** (`gh issue list`) to confirm what's next and pull any
  context/discussion added there since the roadmap was written.
- **An issue is only closed** when its Tests and Docs checkboxes are both satisfied (Section 6.1) —
  closing comment includes the test output/command used to verify, per Section 6.3 point 5.
- If scope changes mid-phase, we update the issue (and this ROADMAP) rather than silently drifting.

---

### Next step
Phases 0–3 are complete: the repo scaffold, the Spring Boot app, its Docker image, and a local `kind`
Kubernetes cluster (with the image loaded in) all exist and pass their gates. Next up is **Phase 4** —
write `k8s/deployment.yaml` and `k8s/service.yaml` and get the app running as self-healing Pods.
