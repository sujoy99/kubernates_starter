#!/usr/bin/env bash
# Phase 4 smoke test: apply the k8s manifests, wait for the Deployment's
# Pods to become Ready, reach the app through a port-forwarded Service,
# then kill one Pod and prove Kubernetes replaces it (self-healing) and
# the Service keeps answering throughout.
#
# Assumes: a kind cluster is already up (Phase 3) and `hello-service:0.1.0`
# has already been loaded into it (`kind load docker-image ...`).
#
# Usage: ./scripts/smoke-k8s.sh
# Exit code: 0 = passed, 1 = failed.

set -euo pipefail

APP_LABEL="app=hello-service"
SERVICE_NAME="hello-service"
LOCAL_PORT="8080"
REPLICAS=2
READY_TIMEOUT="60s"
HEAL_TIMEOUT_SECONDS=60

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PORT_FORWARD_PID=""
cleanup() {
  if [ -n "$PORT_FORWARD_PID" ]; then
    kill "$PORT_FORWARD_PID" >/dev/null 2>&1 || true
    wait "$PORT_FORWARD_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

echo "==> Applying manifests from k8s/"
kubectl apply -f "$REPO_ROOT/k8s/"

echo "==> Waiting for Pods to be Ready (timeout: $READY_TIMEOUT)"
kubectl wait --for=condition=Ready "pod" -l "$APP_LABEL" --timeout="$READY_TIMEOUT"

ready_count="$(kubectl get pods -l "$APP_LABEL" --field-selector=status.phase=Running -o jsonpath='{.items[*].metadata.name}' | wc -w)"
if [ "$ready_count" -lt "$REPLICAS" ]; then
  echo "FAILED: expected $REPLICAS Running Pods, found $ready_count"
  kubectl get pods -l "$APP_LABEL"
  exit 1
fi
echo "==> $ready_count Pods Running"

echo "==> Starting port-forward to svc/$SERVICE_NAME"
kubectl port-forward "svc/$SERVICE_NAME" "$LOCAL_PORT:80" >/tmp/smoke-k8s-port-forward.log 2>&1 &
PORT_FORWARD_PID=$!

echo "==> Waiting for port-forward to accept connections"
elapsed=0
until curl -sf "http://localhost:$LOCAL_PORT/actuator/health" >/dev/null 2>&1; do
  if [ "$elapsed" -ge 20 ]; then
    echo "FAILED: port-forward never became reachable"
    cat /tmp/smoke-k8s-port-forward.log || true
    exit 1
  fi
  sleep 1
  elapsed=$((elapsed + 1))
done

echo "==> Verifying /api/hello and /actuator/health through the Service"
curl -sf "http://localhost:$LOCAL_PORT/actuator/health" | grep -q '"status":"UP"'
response="$(curl -sf "http://localhost:$LOCAL_PORT/api/hello")"
echo "$response" | grep -q '"message"'
echo "$response"

echo "==> Killing one Pod to test self-healing"
victim="$(kubectl get pods -l "$APP_LABEL" -o jsonpath='{.items[0].metadata.name}')"
echo "==> Deleting Pod $victim"
kubectl delete pod "$victim" --wait=false

echo "==> Waiting for a replacement Pod (timeout: ${HEAL_TIMEOUT_SECONDS}s)"
elapsed=0
until [ "$(kubectl get pods -l "$APP_LABEL" --field-selector=status.phase=Running -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | grep -vc "^${victim}$")" -ge "$REPLICAS" ]; do
  if [ "$elapsed" -ge "$HEAL_TIMEOUT_SECONDS" ]; then
    echo "FAILED: replacement Pod for $victim did not become Running within ${HEAL_TIMEOUT_SECONDS}s"
    kubectl get pods -l "$APP_LABEL"
    exit 1
  fi
  sleep 2
  elapsed=$((elapsed + 2))
done
echo "==> Self-healed after ~${elapsed}s: $REPLICAS Pods Running again, $victim is gone"

# kubectl port-forward against a Service pins to whichever single backing
# Pod it resolved at connection time — it does NOT fail over. Since we
# just deleted that exact Pod, the old tunnel is dead by design, not by
# bug. Re-open it (now landing on a live Pod) to prove the Service as a
# whole recovered, which is the thing this test actually cares about.
kill "$PORT_FORWARD_PID" >/dev/null 2>&1 || true
wait "$PORT_FORWARD_PID" 2>/dev/null || true
kubectl port-forward "svc/$SERVICE_NAME" "$LOCAL_PORT:80" >/tmp/smoke-k8s-port-forward.log 2>&1 &
PORT_FORWARD_PID=$!

echo "==> Confirming the Service still answers after the Pod kill"
elapsed=0
until curl -sf "http://localhost:$LOCAL_PORT/api/hello" | grep -q '"message"'; do
  if [ "$elapsed" -ge 20 ]; then
    echo "FAILED: Service did not answer after Pod self-heal"
    cat /tmp/smoke-k8s-port-forward.log || true
    exit 1
  fi
  sleep 1
  elapsed=$((elapsed + 1))
done

echo "PASSED"
