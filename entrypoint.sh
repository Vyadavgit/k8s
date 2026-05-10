#!/bin/bash
# Note: no set -e — we handle errors explicitly so kubectl errors don't kill the container

# Verify the host Docker socket is accessible
echo "==> Checking Docker socket..."
until docker info > /dev/null 2>&1; do
    echo "    Waiting for Docker socket..."
    sleep 2
done
echo "==> Docker socket OK."

# Delete any pre-existing kind cluster
kind delete cluster --name k8s-lab 2>/dev/null || true
docker network rm kind 2>/dev/null || true

echo "==> Creating Kubernetes cluster with kind..."
kind create cluster \
    --name k8s-lab \
    --config /kind-config.yaml \
    --wait 5m

# Connect THIS container to the kind network so kubectl can reach the API server
echo "==> Joining kind network..."
SELF=$(cat /etc/hostname)
docker network connect kind "${SELF}" 2>/dev/null || true
sleep 2  # wait for IP assignment

# Patch kubeconfig: replace 127.0.0.1:<random> with the control-plane container's
# IP on the kind network, which is now reachable from this container.
echo "==> Patching kubeconfig server address..."
KIND_CP_IP=$(docker inspect k8s-lab-control-plane \
    --format '{{index .NetworkSettings.Networks "kind" "IPAddress"}}' 2>/dev/null)
if [ -n "$KIND_CP_IP" ]; then
    sed -i "s|server: https://127.0.0.1:[0-9]*|server: https://${KIND_CP_IP}:6443|g" "${KUBECONFIG}"
    echo "    API server: https://${KIND_CP_IP}:6443"
fi

# Wait for API server to be reachable
echo "==> Waiting for API server to be reachable..."
until kubectl cluster-info > /dev/null 2>&1; do
    sleep 2
done

echo ""
echo "==> Cluster nodes:"
kubectl get nodes -o wide

echo ""
echo "==> All pods:"
kubectl get po -A

echo ""
echo "========================================"
echo "  Kubernetes cluster is ready!"
echo ""
echo "  kubectl get nodes"
echo "  kubectl get po -A"
echo "  kubectl get svc -A"
echo "  kubectl describe node k8s-lab-control-plane"
echo "========================================"
echo ""

exec tail -f /dev/null

echo ""
echo "==> Cluster nodes:"
kubectl get nodes -o wide

echo ""
echo "==> All pods (some may still be initializing - this is normal):"
kubectl get po -A

echo ""
echo "========================================"
echo "  Kubernetes cluster is ready!"
echo ""
echo "  kubectl get nodes"
echo "  kubectl get po -A"
echo "  kubectl get svc -A"
echo "========================================"
echo ""

exec tail -f /dev/null"
echo "  Minikube is ready!"
echo "  kubectl get po -A"
echo "  kubectl get nodes"
echo "  minikube dashboard"
echo "========================================"
echo ""

exec tail -f /dev/null
