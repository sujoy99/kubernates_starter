# kubernates-starter — Spring Boot Microservice on Kubernetes (POC)

A beginner-friendly, production-grade-practices POC: a Dockerized Spring Boot microservice, orchestrated
by Kubernetes, built one understood phase at a time.

**New here? Start with [ROADMAP.md](ROADMAP.md).** It's the single source of truth for the plan, the
tech choices (and why), the vocabulary you need, and the quality gates (tests + docs) every phase must
pass. This README is just the quick-start once the app exists.

## Status

Work is tracked as [GitHub Issues](../../issues), one per phase (`phase-0` … `phase-10`). Check there
for what's currently in progress. See [ROADMAP.md](ROADMAP.md) Section 7 for the full phase list.

## Quick start

> Not runnable yet — this section fills in as Phases 1–4 land. Placeholder commands below show the
> shape of what's coming.

```bash
# Phase 1+: run the app locally
cd app && mvn spring-boot:run
curl http://localhost:8080/api/hello
curl http://localhost:8080/actuator/health

# Phase 2+: build & run in Docker
docker build -t hello-service:0.1.0 ./app
docker run -p 8080:8080 hello-service:0.1.0

# Phase 3+: local Kubernetes cluster
kind create cluster --name poc
kind load docker-image hello-service:0.1.0 --name poc

# Phase 4+: deploy
kubectl apply -f k8s/
kubectl get pods
kubectl port-forward svc/hello-service 8080:80
```

## Docs

Per-phase, beginner-friendly write-ups live in [`docs/`](docs/) — what was built, why, how to reproduce
it, how it was tested, and gotchas hit along the way.

## kubectl cheat-sheet

See [ROADMAP.md Section 9](ROADMAP.md#9-kubectl-survival-kit-bookmark-this) for the commands you'll use daily.
