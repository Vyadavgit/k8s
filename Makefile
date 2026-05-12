.PHONY: build rebuild up down clean shell k logs deploy dashboard

# ──────────────────────────────────────────────
# Image
# ──────────────────────────────────────────────

## Build the Docker image (cached)
build:
	docker compose build

## Force a clean rebuild with no cache
rebuild:
	docker compose build --no-cache

# ──────────────────────────────────────────────
# Cluster lifecycle
# ──────────────────────────────────────────────

## Start cluster + deploy all manifests
up:
	@echo ""
	@echo "==> [1/4] Cleaning up any prior kind containers..."
	@docker rm -f k8s-lab k8s-lab-control-plane k8s-lab-worker k8s-lab-worker2 2>/dev/null || true
	@docker network rm kind 2>/dev/null || true
	@echo ""
	@echo "==> [2/4] Starting k8s-lab container..."
	@docker compose up -d
	@echo ""
	@echo "==> [3/4] Waiting for cluster to be ready..."
	@until docker exec k8s-lab kubectl get nodes 2>/dev/null | grep -q "Ready"; do \
		echo "    ... waiting for nodes"; sleep 5; \
	done
	@echo "    ✓ Nodes ready"
	@until docker exec k8s-lab kubectl get po -n kube-system 2>/dev/null | grep coredns | grep -q "Running"; do \
		echo "    ... waiting for CoreDNS"; sleep 5; \
	done
	@echo "    ✓ CoreDNS ready"
	@echo ""
	@echo "==> [4/4] Deploying workload manifests..."
	@docker exec k8s-lab kubectl apply -f /workspace/manifests/
	@echo "==> Waiting for rollouts..."
	@docker exec k8s-lab kubectl rollout status deployment/hello-api --timeout=90s 2>/dev/null || true
	@docker exec k8s-lab kubectl rollout status deployment/nginx --timeout=90s 2>/dev/null || true
	@echo ""
	@echo "  ✓ Cluster is up and running!"
	@echo "  ✓ hello-api  → http://localhost:30081"
	@echo "  ✓ nginx      → http://localhost:30080"
	@echo ""
	@echo "  Run 'make dashboard' to install and open the Kubernetes Dashboard."
	@echo ""

## Stop dashboard port-forward, remove all containers and networks (full shutdown)
down:
	@echo ""
	@echo "==> Stopping dashboard port-forward..."
	@pkill -f "kubectl port-forward" 2>/dev/null || true
	@echo "==> Removing containers..."
	@docker rm -f k8s-lab k8s-lab-control-plane k8s-lab-worker k8s-lab-worker2 2>/dev/null || true
	@echo "==> Removing kind network..."
	@docker network rm kind 2>/dev/null || true
	@echo "==> Stopping compose..."
	@docker compose down --remove-orphans 2>/dev/null || true
	@echo ""
	@echo "  ✓ Cluster stopped and cleaned up."

## Full reset: down + delete kubeconfig volume
clean: down
	@docker volume rm k8s-kube-config 2>/dev/null || true
	@echo "  ✓ Volume removed. Run 'make build && make up' for a fresh start."

# ──────────────────────────────────────────────
# Day-to-day operations
# ──────────────────────────────────────────────

## Attach an interactive shell to the lab container
shell:
	docker exec -it k8s-lab bash

## Run a kubectl command from the host
## Usage: make k CMD="get nodes -o wide"
k:
	@test -n "$(CMD)" || (echo "Usage: make k CMD=\"get nodes -o wide\"" && exit 1)
	@docker exec k8s-lab kubectl $(CMD)

## Tail the k8s-lab container logs
logs:
	docker logs -f k8s-lab

## Re-apply workload manifests (cluster must already be running)
deploy:
	@echo "==> Applying manifests..."
	@docker exec k8s-lab kubectl apply -f /workspace/manifests/
	@echo "==> Waiting for rollouts..."
	@docker exec k8s-lab kubectl rollout status deployment/hello-api --timeout=90s 2>/dev/null || true
	@docker exec k8s-lab kubectl rollout status deployment/nginx --timeout=90s 2>/dev/null || true
	@echo ""
	@docker exec k8s-lab kubectl get svc
	@echo ""
	@echo "  hello-api  → http://localhost:30081"
	@echo "  nginx      → http://localhost:30080"
	@echo ""
	@echo "  Run 'make dashboard' to install/refresh the Kubernetes Dashboard."

# ──────────────────────────────────────────────
# Dashboard  (run after 'make up' when cluster is fully ready)
# ──────────────────────────────────────────────

## Install the Kubernetes Dashboard, wait until ready, enable skip-login, start port-forward
dashboard:
	@echo ""
	@echo "==> Installing Kubernetes Dashboard..."
	@docker exec k8s-lab kubectl apply -f /workspace/manifests/dashboard-admin.yaml
	@docker exec k8s-lab kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml
	@echo ""
	@echo "==> Waiting for dashboard pod to be Running (may take ~60s on first install)..."
	@docker exec k8s-lab kubectl rollout status deployment/kubernetes-dashboard \
		-n kubernetes-dashboard --timeout=180s
	@until docker exec k8s-lab kubectl get pod -n kubernetes-dashboard \
		-l k8s-app=kubernetes-dashboard 2>/dev/null | grep -q "Running"; do \
		echo "    ... waiting for dashboard pod"; sleep 5; \
	done
	@echo "    ✓ Dashboard pod Running"
	@echo ""
	@echo "==> Enabling skip-login..."
	@docker exec k8s-lab kubectl patch deployment kubernetes-dashboard \
		-n kubernetes-dashboard \
		--type=json -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--enable-skip-login"},{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--disable-settings-authorizer"}]' \
		2>/dev/null || true
	@echo "==> Waiting for patched pod to be Ready..."
	@sleep 5
	@docker exec k8s-lab kubectl rollout status deployment/kubernetes-dashboard \
		-n kubernetes-dashboard --timeout=90s
	@echo "    ✓ Dashboard ready"
	@echo ""
	@echo "==> Starting dashboard port-forward..."
	@pkill -f "kubectl port-forward.*8443" 2>/dev/null || true
	@sleep 1
	@docker exec k8s-lab kubectl port-forward --address 0.0.0.0 \
		-n kubernetes-dashboard svc/kubernetes-dashboard 8443:443 &>/dev/null &
	@sleep 3
	@echo ""
	@echo "  ✓ dashboard → https://localhost:8443"
	@echo "  Click 'Skip' on the login page, or paste the token below:"
	@echo ""
	@echo "  Static token (no expiry):"
	@docker exec k8s-lab kubectl get secret admin-user-token \
		-n kubernetes-dashboard -o jsonpath='{.data.token}' | base64 -d
	@echo ""
	@echo ""
	@echo "  TIP: Dashboard opens on the 'default' namespace."
	@echo "       Change the namespace dropdown (top-left) to 'All namespaces'"
	@echo "       to see hello-api and nginx workloads."
	@echo ""
