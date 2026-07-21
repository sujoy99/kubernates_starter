#!/usr/bin/env bash
# Phase 2 smoke test: build the Docker image, run it, poll /actuator/health
# until it reports UP (or time out and fail loudly), then clean up.
#
# Usage: ./scripts/smoke-docker.sh
# Exit code: 0 = passed, 1 = failed.

set -euo pipefail

IMAGE="hello-service:0.1.0"
CONTAINER_NAME="hello-service-smoke-test"
HOST_PORT="8080"
TIMEOUT_SECONDS=30

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cleanup() {
  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "==> Building image $IMAGE"
docker build -t "$IMAGE" "$REPO_ROOT/app"

echo "==> Removing any leftover container named $CONTAINER_NAME"
cleanup

echo "==> Starting container"
docker run -d --name "$CONTAINER_NAME" -p "$HOST_PORT:8080" "$IMAGE" >/dev/null

echo "==> Polling http://localhost:$HOST_PORT/actuator/health (timeout: ${TIMEOUT_SECONDS}s)"
elapsed=0
until curl -sf "http://localhost:$HOST_PORT/actuator/health" | grep -q '"status":"UP"'; do
  if [ "$elapsed" -ge "$TIMEOUT_SECONDS" ]; then
    echo "FAILED: container did not report healthy within ${TIMEOUT_SECONDS}s"
    echo "---- container logs ----"
    docker logs "$CONTAINER_NAME" || true
    exit 1
  fi
  sleep 1
  elapsed=$((elapsed + 1))
done

echo "==> Healthy after ${elapsed}s. Verifying /api/hello"
response="$(curl -sf "http://localhost:$HOST_PORT/api/hello")"
echo "$response" | grep -q '"message"'

echo "PASSED"
echo "$response"
