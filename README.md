# Local Kubernetes Lab (kind + Docker)

A containerized Kubernetes environment running a 3-node cluster (1 control-plane + 2 workers) using [kind](https://kind.sigs.k8s.io/) inside Docker. Purpose-built for exploring Kubernetes networking, deployments, services, and internals on macOS.

## Architecture

```
┌─────────────────────────────────────────────────┐
│  macOS Host                                     │
│                                                 │
│  ┌────────────────────────────────────────────┐ │
│  │  k8s-lab container (Ubuntu 22.04)          │ │
│  │  • kubectl  • kind  • networking tools     │ │
│  │                                            │ │
│  │  ┌──────────────┐  ┌────────┐  ┌────────┐  │ │
│  │  │ control-plane│  │worker  │  │worker2 │  │ │
│  │  │ (k8s API,    │  │        │  │        │  │ │
│  │  │  etcd,       │  │        │  │        │  │ │
│  │  │  scheduler)  │  │        │  │        │  │ │
│  │  └──────────────┘  └────────┘  └────────┘  │ │
│  │         Docker "kind" bridge network       │ │
│  └────────────────────────────────────────────┘ │
│              /var/run/docker.sock (mounted)     │
└─────────────────────────────────────────────────┘
```

## Prerequisites

- [Docker Desktop for Mac](https://www.docker.com/products/docker-desktop/) (>= 4.x)
- Docker Desktop resource settings: **≥ 4 GB RAM**, **≥ 2 CPUs**

## Project Structure

```
k8s/
├── Dockerfile          # Ubuntu image with kubectl, kind, and network tools
├── docker-compose.yml  # Compose service definition
├── entrypoint.sh       # Bootstraps the kind cluster on container start
├── kind-config.yaml    # kind cluster configuration (nodes, networking, CNI)
├── manifests/          # Drop your YAML manifests here — mounted at /workspace/manifests
└── README.md
```

## Quick Start

### Option A — Makefile (recommended)

```bash
make build      # build the image
make up         # start cluster + tail logs until ready
make shell      # attach interactive shell
make down       # stop everything
make clean      # stop + delete kubeconfig volume
```

Run a one-off kubectl command from your Mac without shelling in:
```bash
make k CMD="get nodes -o wide"
make k CMD="get po -A"
make k CMD="apply -f /workspace/manifests/example.yaml"
```

---

### Option B — docker compose

#### 1. Build the image

```bash
docker compose build
```

> Add `--no-cache` for a fully fresh build.

#### 2. Clean up any prior kind containers (important on restart)

```bash
docker rm -f k8s-lab k8s-lab-control-plane k8s-lab-worker k8s-lab-worker2 2>/dev/null
docker network rm kind 2>/dev/null
```

#### 3. Start the cluster

```bash
docker compose up -d
```

#### 4. Tail startup logs

```bash
docker logs -f k8s-lab
```

Wait for this output before proceeding (~60-90s on first run, ~30s after):
```
✓ Starting control-plane
✓ Installing CNI
✓ Joining worker nodes
✓ Waiting for control-plane = Ready — Ready after 12s
========================================
  Kubernetes cluster is ready!
========================================
```

#### 5. Attach a shell to the container

```bash
docker exec -it k8s-lab bash
```

You're now inside an Ubuntu shell with `kubectl` and `kind` on `$PATH`, pointed at your live cluster.

#### 6. Verify the cluster

```bash
# From inside the container
kubectl get nodes -o wide
kubectl get po -A
```

Expected output:
```
NAME                    STATUS   ROLES           AGE   VERSION
k8s-lab-control-plane   Ready    control-plane   60s   v1.35.0
k8s-lab-worker          Ready    <none>          50s   v1.35.0
k8s-lab-worker2         Ready    <none>          50s   v1.35.0
```

#### 7. Stop the cluster

```bash
docker compose down

# Also remove the kind node containers and network
docker rm -f k8s-lab-control-plane k8s-lab-worker k8s-lab-worker2 2>/dev/null
docker network rm kind 2>/dev/null
```

---

### Option C — Run kubectl from your Mac (no shell needed)

You don't need to shell into the container for every command:

```bash
# One-off commands
docker exec k8s-lab kubectl get nodes
docker exec k8s-lab kubectl get po -A
docker exec k8s-lab kubectl apply -f /workspace/manifests/example.yaml

# Open an interactive kubectl session on the host
docker exec -it k8s-lab kubectl exec -it <pod-name> -- sh
```

---

## Using kubectl

All commands run **inside the container** shell (`docker exec -it k8s-lab bash`).

```bash
# Cluster info
kubectl cluster-info
kubectl get nodes -o wide
kubectl get po -A                        # all pods across all namespaces

# Shorthand alias (pre-configured)
k get nodes
k get po -A
```

---

## Deploying Applications

### Deploy an nginx web server

```bash
# Create a deployment
kubectl create deployment nginx --image=nginx

# Expose it as a NodePort service
kubectl expose deployment nginx --port=80 --type=NodePort

# Check it's running
kubectl get po
kubectl get svc nginx

# Get the NodePort assigned (30000-32767)
kubectl get svc nginx -o jsonpath='{.spec.ports[0].nodePort}'
```

### Apply a manifest from the manifests/ folder

Put any YAML file in `./manifests/` on your Mac — it's live-mounted at `/workspace/manifests` inside the container.

```bash
kubectl apply -f /workspace/manifests/my-deployment.yaml
kubectl get all
```

---

## Deploy & Test nginx

A ready-to-use nginx manifest is included at [`manifests/ngnix.yaml`](manifests/ngnix.yaml) (2 replicas, NodePort 30080).

### 1. Shell into the container

```bash
make shell
# or
docker exec -it k8s-lab bash
```

### 2. Apply the manifest

```bash
kubectl apply -f /workspace/manifests/ngnix.yaml
```

### 3. Wait for pods to be Running

```bash
kubectl get pods -l app=nginx -w
# Press Ctrl+C once STATUS shows Running for both pods
```

Expected:
```
NAME                     READY   STATUS    RESTARTS   AGE
nginx-xxxx-aaaaa         1/1     Running   0          15s
nginx-xxxx-bbbbb         1/1     Running   0          15s
```

### 4. Verify the Service

```bash
kubectl get svc nginx
```

Expected:
```
NAME    TYPE       CLUSTER-IP     EXTERNAL-IP   PORT(S)        AGE
nginx   NodePort   10.96.x.x      <none>        80:30080/TCP   20s
```

### 5a. Test via ClusterIP (inside the container)

```bash
# Spin up a temporary curl pod and hit the nginx service by DNS name
kubectl run curl-test --image=curlimages/curl --rm -it --restart=Never \
  -- curl -s http://nginx:80
```

You should see the nginx welcome HTML.

### 5b. Test via port-forward (from your Mac)

```bash
# Run inside the container (or in a second terminal via docker exec)
kubectl port-forward svc/nginx 8080:80
```

Then open **http://localhost:8080** in your Mac browser — you'll see the **"Welcome to nginx!"** page.

### 6. Check nginx logs

```bash
kubectl logs -l app=nginx
```

### 7. Describe a pod (debugging)

```bash
kubectl describe pod -l app=nginx
```

### 8. Teardown

```bash
kubectl delete -f /workspace/manifests/ngnix.yaml
# or from your Mac:
make k CMD="delete -f /workspace/manifests/ngnix.yaml"
```

### Example deployment manifest

```yaml
# manifests/example.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hello
spec:
  replicas: 3
  selector:
    matchLabels:
      app: hello
  template:
    metadata:
      labels:
        app: hello
    spec:
      containers:
        - name: hello
          image: nginxdemos/hello
          ports:
            - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: hello
spec:
  type: NodePort
  selector:
    app: hello
  ports:
    - port: 80
      targetPort: 80
      nodePort: 30080
```

```bash
kubectl apply -f /workspace/manifests/example.yaml
kubectl get po -l app=hello
kubectl get svc hello
```

---

## Exploring the Network Layer

```bash
# See pod IPs and which node they're on
kubectl get po -A -o wide

# See service ClusterIPs and NodePorts
kubectl get svc -A

# Inspect the CNI (kindnet) networking on a node
kubectl describe node k8s-lab-control-plane | grep -A5 "Addresses"

# Look at iptables rules (kube-proxy)
docker exec k8s-lab-control-plane iptables -t nat -L KUBE-SERVICES --line-numbers | head -30

# Trace a pod's network namespace
kubectl get po -n kube-system -o wide   # find a pod
docker exec k8s-lab-control-plane ip route

# DNS resolution inside the cluster
kubectl run dnstest --image=busybox --rm -it --restart=Never -- nslookup kubernetes.default
```

---

## Exploring Core Components

```bash
# etcd — the cluster state store
kubectl get po -n kube-system | grep etcd
kubectl exec -it etcd-k8s-lab-control-plane -n kube-system -- \
  etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  get / --prefix --keys-only | head -20

# API server logs
kubectl logs kube-apiserver-k8s-lab-control-plane -n kube-system | tail -20

# Scheduler logs
kubectl logs kube-scheduler-k8s-lab-control-plane -n kube-system | tail -20

# Controller manager logs
kubectl logs kube-controller-manager-k8s-lab-control-plane -n kube-system | tail -20
```

---

## Cluster Configuration

Cluster topology is defined in [`kind-config.yaml`](kind-config.yaml):

| Setting | Value |
|---|---|
| Control-plane nodes | 1 |
| Worker nodes | 2 |
| Pod subnet | `10.244.0.0/16` |
| Service subnet | `10.96.0.0/12` |
| CNI | kindnet (default) |
| Kubernetes version | v1.35.0 |

To add more worker nodes, append to `kind-config.yaml`:
```yaml
  - role: worker
```
Then rebuild and restart.

To swap the CNI (e.g. install Calico for learning network policy), set `disableDefaultCNI: true` in `kind-config.yaml` and apply a CNI manifest after cluster creation.

---

## Installed Tools

| Tool | Purpose |
|---|---|
| `kubectl` | Kubernetes CLI |
| `kind` | Cluster lifecycle management |
| `docker` (CLI) | Interact with host Docker daemon |
| `tcpdump` | Capture network traffic |
| `iproute2` / `ip` | Inspect routes, interfaces |
| `dnsutils` / `dig` | DNS debugging |
| `netstat` / `ss` | Socket and port inspection |
| `curl` | HTTP testing |
| `vim` | Edit files in-container |

---

## Troubleshooting

**Container exits immediately**
```bash
docker logs k8s-lab
```
Check for port conflicts or Docker socket permission issues.

**`kubectl` connection refused**
```bash
# Verify the container is on the kind network
docker network inspect kind | grep k8s-lab

# If missing, connect it
docker network connect kind k8s-lab

# Verify the kubeconfig has the right IP
cat /root/.kube/config | grep server
```

**Port already allocated on start**
```bash
# Find what's using the port
lsof -i :6443

# Or remove all kind containers and try again
docker rm -f k8s-lab k8s-lab-control-plane k8s-lab-worker k8s-lab-worker2
docker network rm kind
```

**Node NotReady**
```bash
kubectl describe node <node-name>
kubectl get events -A --sort-by=.lastTimestamp | tail -20
```
