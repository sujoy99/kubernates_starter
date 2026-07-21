# Phase 3 — A local Kubernetes cluster

## What we built

A local, single-node Kubernetes cluster running via `kind` ("Kubernetes IN Docker"), named `poc`, and
loaded the `hello-service:0.1.0` image (from Phase 2) into it so the cluster can run it without pulling
from any registry.

## Why

Kubernetes needs somewhere to run. A real cloud cluster costs money and adds setup overhead you don't
need while learning — `kind` runs an entire single-node Kubernetes cluster *inside a Docker container* on
your own laptop, in a couple of minutes, for free. This is the "restaurant building" from the
[ROADMAP's mental model](../ROADMAP.md#1-the-30-second-mental-model): before Kubernetes (the head chef)
can run anything, it needs a node (a building) to run it on.

The crucial gotcha this phase teaches: a local cluster is *isolated* from your machine's Docker image
cache. Building `hello-service:0.1.0` with `docker build` puts the image in your laptop's Docker, but the
kind cluster's own internal container runtime (`containerd`) can't see it until you explicitly
`kind load docker-image` it in. Skip that step and Phase 4's `kubectl apply` will fail with
`ImagePullBackOff`, because the cluster will try (and fail) to pull `hello-service:0.1.0` from a public
registry that doesn't have it.

## New concepts introduced

- **Cluster** — a set of machines (nodes) managed together by Kubernetes as one unit. `kind` gives you a
  cluster with exactly one node, which plays both control-plane and worker roles — plenty for a POC.
- **Node** — a single machine (real or virtual) that Kubernetes runs containers on. With `kind`, a "node"
  is actually a Docker container pretending to be a full machine (it runs its own `containerd`, `kubelet`,
  etc. inside).
- **kubectl context** — `kubectl` can talk to many clusters; the *context* says which one (and which
  credentials/namespace) your commands currently target. Creating a kind cluster automatically adds and
  switches to a `kind-poc` context.

## Step-by-step reproduction

```bash
# Install kind (Windows, via winget; see kind's docs for other OSes)
winget install --id Kubernetes.kind -e

# Create a one-node cluster named "poc"
kind create cluster --name poc

# Confirm the node exists and is healthy
kubectl get nodes
# NAME                STATUS   ROLES           AGE   VERSION
# poc-control-plane   Ready    control-plane   38s   v1.36.1

kubectl cluster-info
# Kubernetes control plane is running at https://127.0.0.1:<port>
# CoreDNS is running at https://127.0.0.1:<port>/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy

# Make sure the app image exists locally (built in Phase 2)
docker build -t hello-service:0.1.0 ./app

# Load it into the kind cluster's internal image store
kind load docker-image hello-service:0.1.0 --name poc

# Prove it actually landed on the node (kind's node is a container; crictl is its image CLI)
docker exec poc-control-plane crictl images | grep hello-service
# docker.io/library/hello-service   0.1.0   <id>   93.9MB
```

## How we tested it

**Automated (the Phase 3 gate):**

```bash
kubectl get nodes
# poc-control-plane   Ready   control-plane   ...

kubectl cluster-info
# succeeds, prints control-plane and CoreDNS URLs
```

**Manual:** ran `docker exec poc-control-plane crictl images` and confirmed `hello-service:0.1.0`
(93.9MB, matching the image size from Phase 2) is present in the node's own image store — proof the
`kind load docker-image` step actually worked, not just that the `docker build` succeeded on the host.

## Common errors & fixes

- **`kind` not installed.** Not preinstalled with Docker Desktop. On Windows, installed via
  `winget install --id Kubernetes.kind -e`. After install, the shell's `PATH` isn't updated until you open
  a new terminal session.

- **Cluster creation fails with a `kubeadm` bootstrap timeout** (`failed to init node with kubeadm ...
  client rate limiter Wait returned an error: context deadline exceeded`, stuck retrying
  `POST .../clusterrolebindings`). This happened twice in a row on this machine. Root cause: a **stale
  Docker network named `kind`** left over from a previous failed/deleted cluster — it had picked up a
  dual-stack (IPv4+IPv6) config that made container-to-container traffic between the node's etcd/apiserver
  flaky enough to blow past kubeadm's internal deadline, even though individual retries looked fine.
  Fix: `docker network rm kind` (only safe when no kind cluster is currently using it — check
  `docker network inspect kind` shows no containers first), then `kind create cluster` again so it
  recreates the network fresh. *(We initially suspected the WSL2 "mirrored" networking mode setting and
  toggled it off, then back on — that turned out to be a red herring; the network recreation was the
  actual fix, and mirrored mode was restored to its original setting.)*

- **`docker build` fails mid-way with `Name or service not known` resolving a Maven repo host.** A
  one-off DNS blip inside the build container during a long (multi-minute) dependency download — not
  reproducible, resolved by simply re-running `docker build`. If it persists, check DNS resolution
  directly: `docker run --rm alpine:3.20 nslookup repo.maven.apache.org`.

- **Docker Desktop / WSL2 needs a restart** (e.g. after changing `.wslconfig`) — `wsl --shutdown` followed
  by relaunching Docker Desktop. Note this does **not** necessarily destroy existing containers (including
  a running kind cluster) if the underlying WSL2 distro's disk persists — check `docker ps -a` before
  assuming you need to recreate anything.
