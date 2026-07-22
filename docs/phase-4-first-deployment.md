# Phase 4 — First deployment to Kubernetes

## What we built

Two Kubernetes manifests — `k8s/deployment.yaml` and `k8s/service.yaml` — that run `hello-service:0.1.0`
(from Phase 2/3) as **2 self-healing Pods** behind a stable internal address, with health probes wired
to the Actuator endpoint from Phase 1.

## Why

This is the "head chef" (Kubernetes) actually cooking, from the
[ROADMAP's mental model](../ROADMAP.md#1-the-30-second-mental-model). Up to now we had a recipe (the
app), a meal-kit box (the image), and a building (the `kind` node) — but nothing running yet. A
**Deployment** is the object that says "always keep N healthy copies of this Pod running"; a **Service**
gives those Pods (whose IPs change every time one is recreated) one unchanging name other things can
reach. Together they turn "an image that exists" into "an app that's actually up and self-healing."

## New concepts introduced

- **Pod** — the smallest thing Kubernetes runs, usually one container. Our Pod runs the
  `hello-service` container on port 8080.
- **Deployment** — declares the desired state ("2 replicas of this Pod spec") and continuously
  reconciles reality toward it. If a Pod dies, the Deployment (via its ReplicaSet) creates a new one.
- **ReplicaSet** — the controller a Deployment creates under the hood to actually count and replace
  Pods. You manage the Deployment; the ReplicaSet is mostly invisible day-to-day.
- **Service (ClusterIP)** — a stable virtual IP + DNS name (`hello-service`) that load-balances across
  whichever Pods currently match its label selector. Reachable only from inside the cluster for now —
  we get to it via `kubectl port-forward` until Phase 6 adds an Ingress.
- **Liveness / readiness probes** — HTTP health checks kubelet runs against each Pod. *Readiness*
  gates whether the Service sends the Pod traffic; *liveness* decides whether kubelet should kill and
  restart the container. Both point at `/actuator/health`, the endpoint Phase 1 already exposed.
- **Resource requests/limits** — `requests` is what the scheduler reserves (used to pick a node);
  `limits` is the hard ceiling the container can't exceed. See the CPU-throttling gotcha below for why
  the exact numbers matter more than they look like they should.
- **`kubectl apply --dry-run=client`** — parses and validates YAML against the local `kubectl` schema
  without touching the cluster. Catches typos/structural mistakes before you ever hit a live API server.

## Step-by-step reproduction

```bash
# Make sure the Phase 3 cluster exists and has the image loaded
kind get clusters                                   # expect: poc
docker exec poc-control-plane crictl images | grep hello-service

# Validate the manifests before touching the cluster
kubectl apply -f k8s/ --dry-run=client
# deployment.apps/hello-service created (dry run)
# service/hello-service created (dry run)

# Apply for real
kubectl apply -f k8s/

# The debugging trio
kubectl get pods -l app=hello-service
kubectl describe pod <pod-name>
kubectl logs <pod-name>

# Reach it from your laptop (Service is ClusterIP = cluster-internal only)
kubectl port-forward svc/hello-service 8080:80
curl http://localhost:8080/actuator/health
curl http://localhost:8080/api/hello

# Or run the full gate in one shot (apply, wait for Ready, curl, kill a
# Pod, confirm it's replaced and the Service still answers):
./scripts/smoke-k8s.sh
```

## How we tested it

**Automated (the Phase 4 gate):** `scripts/smoke-k8s.sh` —

```
==> Applying manifests from k8s/
deployment.apps/hello-service unchanged
service/hello-service unchanged
==> Waiting for Pods to be Ready (timeout: 60s)
pod/hello-service-7b9b749b9c-ms2d5 condition met
pod/hello-service-7b9b749b9c-tmchr condition met
==> 2 Pods Running
==> Starting port-forward to svc/hello-service
==> Waiting for port-forward to accept connections
==> Verifying /api/hello and /actuator/health through the Service
{"service":"hello-service","message":"Hello from Kubernetes!"}
==> Killing one Pod to test self-healing
==> Deleting Pod hello-service-7b9b749b9c-ms2d5
pod "hello-service-7b9b749b9c-ms2d5" deleted from default namespace
==> Waiting for a replacement Pod (timeout: 60s)
==> Self-healed after ~4s: 2 Pods Running again, hello-service-7b9b749b9c-ms2d5 is gone
==> Confirming the Service still answers after the Pod kill
PASSED
```

**Manual:**

```
$ kubectl get pods -l app=hello-service -o wide
NAME                             READY   STATUS    RESTARTS   AGE   IP           NODE
hello-service-7b9b749b9c-jhdx8   1/1     Running   0          9m    10.244.0.7   poc-control-plane
hello-service-7b9b749b9c-tmchr   1/1     Running   0          8m    10.244.0.8   poc-control-plane

$ curl http://localhost:8080/actuator/health
{"status":"UP","groups":["liveness","readiness"]}

$ curl http://localhost:8080/api/hello
{"service":"hello-service","message":"Hello from Kubernetes!"}
```

Also confirmed `kubectl describe pod` shows clean `Events` (Scheduled → Pulled → Created → Started, no
`Unhealthy`/`Killing` entries) once the probe timing fix below was in place.

## Common errors & fixes

- **Pods stuck restarting, never reaching `Ready`, with `Warning Unhealthy ... connection refused` in
  `kubectl describe pod`.** Root cause: the first `deployment.yaml` draft set `resources.limits.cpu:
  250m` with `readinessProbe.initialDelaySeconds: 5` / `livenessProbe.initialDelaySeconds: 15` — timings
  that work fine running the same image with `docker run` (no CPU limit) but not under a *hard* CPU
  limit. `kubectl logs` on the struggling Pod showed the JVM was still mid-`ApplicationContext` startup
  30+ seconds in (`Started HelloServiceApplication in 26.594 seconds`) — CPU throttling under `250m`
  (a quarter of a core) slows Spring Boot's startup far more than it feels like it should. The liveness
  probe was killing the container *before it ever finished booting*, so it never got a chance to become
  Ready — an endless restart loop that looks like a crash but isn't one.

  Fix: raised `resources.requests.cpu` to `250m` / `limits.cpu` to `500m`, and gave both probes much more
  slack (`readinessProbe.initialDelaySeconds: 30`, `failureThreshold: 6`;
  `livenessProbe.initialDelaySeconds: 45`). The real, long-term fix for "probes vs. slow JVM startup" is
  a **startup probe** (suppresses liveness/readiness checks entirely until the app reports healthy once)
  — that's introduced in Phase 7; for now, generous `initialDelaySeconds` is the Phase-4-scoped fix.

- **`kubectl port-forward svc/hello-service ...` dies the instant you delete a Pod to test
  self-healing.** This looked like a bug in the self-heal test at first, but it isn't one:
  `kubectl port-forward` against a *Service* resolves to exactly one backing Pod at connection time and
  tunnels straight to it — it does not fail over if that specific Pod disappears, even though the
  Service itself is fine and load-balancing across the *other* Pod the whole time. `scripts/smoke-k8s.sh`
  handles this by tearing down and re-opening the port-forward after the Pod-kill step, before checking
  that the Service still answers.

## Depends on

Phase 3.
