#!/usr/bin/env bash
# Phase 5 regression test: prove config can change with ZERO image rebuilds.
#
# Flow: apply the baseline manifests, push a new ConfigMap value, restart
# the rollout, poll the app until the new value shows up through the
# Service, then assert every Pod's container image digest is byte-for-byte
# identical to before the restart (i.e. only config changed, not code).
# Finally restores the original ConfigMap so the script is safe to re-run.
#
# Assumes: Phase 4's Deployment/Service are already applied and Ready.
#
# Usage: ./scripts/config-regression.sh
# Exit code: 0 = passed, 1 = failed.

set -euo pipefail

APP_LABEL="app=hello-service"
DEPLOYMENT="hello-service"
SERVICE_NAME="hello-service"
LOCAL_PORT="8080"
ROLLOUT_TIMEOUT="300s"
POLL_TIMEOUT_SECONDS=90

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PORT_FORWARD_PID=""
cleanup() {
  if [ -n "$PORT_FORWARD_PID" ]; then
    kill "$PORT_FORWARD_PID" >/dev/null 2>&1 || true
    wait "$PORT_FORWARD_PID" 2>/dev/null || true
  fi
  echo "==> Restoring original ConfigMap so this script stays repeatable"
  kubectl apply -f "$REPO_ROOT/k8s/configmap.yaml" >/dev/null
  kubectl rollout restart "deployment/$DEPLOYMENT" >/dev/null
  kubectl rollout status "deployment/$DEPLOYMENT" --timeout="$ROLLOUT_TIMEOUT" >/dev/null
}
trap cleanup EXIT

start_port_forward() {
  kubectl port-forward "svc/$SERVICE_NAME" "$LOCAL_PORT:80" >/tmp/config-regression-port-forward.log 2>&1 &
  PORT_FORWARD_PID=$!
  elapsed=0
  until curl -sf "http://localhost:$LOCAL_PORT/actuator/health" >/dev/null 2>&1; do
    if [ "$elapsed" -ge 20 ]; then
      echo "FAILED: port-forward never became reachable"
      cat /tmp/config-regression-port-forward.log || true
      exit 1
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
}

echo "==> Ensuring baseline manifests are applied and Ready"
kubectl apply -f "$REPO_ROOT/k8s/" >/dev/null
kubectl rollout status "deployment/$DEPLOYMENT" --timeout="$ROLLOUT_TIMEOUT" >/dev/null

echo "==> Recording image digests before the config change (proves no rebuild later)"
# Deduped (sort -u): a rolling restart briefly runs more Pods than the
# replica count (surge), so a raw per-Pod list can differ in length
# between snapshots even when every Pod is running the exact same image.
# What we actually care about is "did any new image digest ever appear."
before_images="$(kubectl get pods -l "$APP_LABEL" -o jsonpath='{range .items[*]}{.status.containerStatuses[0].imageID}{"\n"}{end}' | sort -u)"
echo "$before_images"

echo "==> Confirming the app currently serves the baseline ConfigMap message"
start_port_forward
baseline_response="$(curl -sf "http://localhost:$LOCAL_PORT/api/hello")"
echo "$baseline_response"

echo "==> Pushing a new ConfigMap value (no image rebuild, no Dockerfile involved)"
NEW_MESSAGE="Config updated by regression test @ $(date +%s)"
kubectl create configmap hello-service-config \
  --from-literal="APP_GREETING_MESSAGE=$NEW_MESSAGE" \
  --from-literal="LOGGING_LEVEL_ROOT=INFO" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null

echo "==> Restarting the rollout so Pods pick up the new env vars"
kubectl rollout restart "deployment/$DEPLOYMENT" >/dev/null
kubectl rollout status "deployment/$DEPLOYMENT" --timeout="$ROLLOUT_TIMEOUT" >/dev/null

echo "==> Polling the Service until the new message appears (timeout: ${POLL_TIMEOUT_SECONDS}s)"
kill "$PORT_FORWARD_PID" >/dev/null 2>&1 || true
wait "$PORT_FORWARD_PID" 2>/dev/null || true
start_port_forward
elapsed=0
until curl -sf "http://localhost:$LOCAL_PORT/api/hello" | grep -qF "$NEW_MESSAGE"; do
  if [ "$elapsed" -ge "$POLL_TIMEOUT_SECONDS" ]; then
    echo "FAILED: new ConfigMap value never showed up through the Service"
    curl -sf "http://localhost:$LOCAL_PORT/api/hello" || true
    exit 1
  fi
  sleep 2
  elapsed=$((elapsed + 2))
done
echo "==> New message live after ~${elapsed}s: $NEW_MESSAGE"

echo "==> Asserting every Pod's image digest is unchanged (config-only change, zero rebuild)"
after_images="$(kubectl get pods -l "$APP_LABEL" -o jsonpath='{range .items[*]}{.status.containerStatuses[0].imageID}{"\n"}{end}' | sort -u)"
echo "$after_images"
if [ "$before_images" != "$after_images" ]; then
  echo "FAILED: image digest changed — this was not a config-only rollout"
  exit 1
fi

echo "PASSED"
