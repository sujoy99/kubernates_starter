# Phase 5 — Configuration & secrets, done right

## What we built

Moved the greeting message and log level out of the Docker image and into a **ConfigMap**
(`k8s/configmap.yaml`), and added a dummy **Secret** (`k8s/secret.yaml`) holding a fake API key,
both wired into the existing Deployment as environment variables. Changing the greeting message now
takes one `kubectl` edit + a rollout restart — no code change, no `docker build`, no new image.

## Why

This is the 12-factor principle of **externalized config**: anything that might differ between
environments (dev/staging/prod) — messages, log verbosity, credentials — should live outside the
artifact you ship, not be baked into it. Baking config into the image means "change a setting" and
"ship new code" become the same risky operation. A **ConfigMap** solves this for ordinary settings; a
**Secret** is the same idea for sensitive values, with the API server treating it a little more
carefully (e.g. `kubectl describe pod` shows *that* a Secret is wired in, never its value).

## New concepts introduced

- **ConfigMap** — a key/value store of non-secret config, created as its own Kubernetes object and
  referenced from a Pod spec. We used `envFrom.configMapRef` to import every key as an environment
  variable in one line, rather than listing each one individually.
- **Secret** — structurally identical to a ConfigMap (base64-encoded, not encrypted, at rest) but
  handled more cautiously by `kubectl` and the API — `describe pod` shows the *reference*, not the
  value. We wired it with a single explicit `env[].valueFrom.secretKeyRef` entry instead of
  `envFrom`, so this file alone documents exactly which sensitive values the Pod receives.
- **`kubectl rollout restart`** — Pods don't watch their ConfigMap/Secret for changes; editing one
  does *nothing* to already-running Pods. A rollout restart replaces every Pod (respecting the same
  rolling-update strategy as a normal deploy), so the new env vars actually take effect.
- **Spring Boot relaxed env-var binding** — no app code changed at all. `application.yml` already
  read `app.greeting.message` via `@Value("${app.greeting.message}")`; Spring Boot automatically maps
  an `APP_GREETING_MESSAGE` environment variable onto that same property, so the ConfigMap's key names
  were chosen to match that convention on purpose.

## Step-by-step reproduction

```bash
# Apply the new ConfigMap + Secret alongside the existing Deployment/Service
kubectl apply -f k8s/

# Prove the message is now config-driven, not hardcoded
kubectl port-forward svc/hello-service 8080:80 &
curl http://localhost:8080/api/hello
# {"service":"hello-service","message":"Hello from a ConfigMap — zero rebuilds needed!"}

# Change config with zero rebuilds: edit the ConfigMap, then restart the rollout
kubectl edit configmap hello-service-config      # or: kubectl apply -f a-new-configmap.yaml
kubectl rollout restart deployment/hello-service
kubectl rollout status deployment/hello-service
curl http://localhost:8080/api/hello             # new message appears

# Confirm the Secret made it into the Pod as an env var, without ever
# printing its value via kubectl itself
kubectl exec deploy/hello-service -- printenv FAKE_API_KEY
kubectl describe pod -l app=hello-service | grep -A1 Environment:
# FAKE_API_KEY:  <set to the key 'FAKE_API_KEY' in secret 'hello-service-secret'>  Optional: false

# Or run the full regression gate in one shot:
./scripts/config-regression.sh
```

## How we tested it

**Automated (the Phase 5 gate):** `scripts/config-regression.sh` — applies the baseline, records
every running Pod's image digest, confirms the baseline ConfigMap message is being served, pushes a
new ConfigMap value, restarts the rollout, polls until the new message appears through the Service,
then asserts the image digest is *still identical* (proving this was a config-only change, not a
disguised redeploy) — and restores the original ConfigMap afterwards so the script is safe to re-run:

```
==> Ensuring baseline manifests are applied and Ready
==> Recording image digests before the config change (proves no rebuild later)
docker.io/library/import-2026-07-21@sha256:78eed739777fd685176770441b1298491ea3701bfe60ddc315a90d1b19f2c0dd
==> Confirming the app currently serves the baseline ConfigMap message
{"service":"hello-service","message":"Hello from a ConfigMap — zero rebuilds needed!"}
==> Pushing a new ConfigMap value (no image rebuild, no Dockerfile involved)
==> Restarting the rollout so Pods pick up the new env vars
==> Polling the Service until the new message appears (timeout: 90s)
==> New message live after ~0s: Config updated by regression test @ 1784764080
==> Asserting every Pod's image digest is unchanged (config-only change, zero rebuild)
docker.io/library/import-2026-07-21@sha256:78eed739777fd685176770441b1298491ea3701bfe60ddc315a90d1b19f2c0dd
PASSED
==> Restoring original ConfigMap so this script stays repeatable
```

**Manual:**

```
$ kubectl exec deploy/hello-service -- printenv | grep -E 'APP_GREETING_MESSAGE|FAKE_API_KEY'
APP_GREETING_MESSAGE=Hello from a ConfigMap — zero rebuilds needed!
FAKE_API_KEY=demo-fake-api-key-abc123

$ kubectl describe pod hello-service-<id> | grep -A1 Environment:
Environment:
      FAKE_API_KEY:  <set to the key 'FAKE_API_KEY' in secret 'hello-service-secret'>  Optional: false
```

`describe pod` confirmed the Secret is wired in by reference only — the actual value never appears in
`describe` output, only in a direct `exec ... printenv` or `get secret -o yaml`, which is the
production-safe way `kubectl` treats Secrets vs. ConfigMaps.

## Common errors & fixes

- **First regression-script run: `kubectl rollout status --timeout=180s` timed out even though the
  rollout eventually succeeded.** On this machine, a `kubectl rollout restart` (like any new
  ReplicaSet rollout) takes noticeably longer in practice than the ~30–35s single-Pod JVM boot time
  measured in Phase 4 — the default rolling-update strategy for 2 replicas does it one Pod at a time
  (`maxSurge: 25% → 1`, `maxUnavailable: 25% → 0`), so a full rollout is roughly two sequential boots
  back-to-back, plus scheduling/API overhead. 180s wasn't enough headroom. Fixed by raising
  `ROLLOUT_TIMEOUT` to `300s` in the script — correctness matters more than a fast test here.

- **Regression script failed with `FAILED: image digest changed` even though nothing was rebuilt.**
  The "before" and "after" image-digest snapshots were compared as raw per-Pod lists. During the
  rolling restart, the Deployment briefly ran **3** Pods (surge: 2 old + 1 new, or vice versa) before
  settling back to 2 — so the "after" snapshot had 3 lines against the "before" snapshot's 2, even
  though every single line held the *exact same digest*. The list-length mismatch was flagged as a
  false failure. Fixed by deduplicating each snapshot (`sort -u`) before comparing — what actually
  matters for this assertion is "did any new image digest ever appear," not "did the Pod count match
  between two arbitrary points in time during a rollout."

## Depends on

Phase 4.
