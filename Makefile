.PHONY: build up down shell k logs clean rebuild

## Build the Docker image
build:
	docker compose build

## Build from scratch (no cache)
rebuild:
	docker compose build --no-cache

## Start the cluster (detached)
up:
	@echo "==> Cleaning up any prior kind containers..."
	@docker rm -f k8s-lab k8s-lab-control-plane k8s-lab-worker k8s-lab-worker2 2>/dev/null || true
	@docker network rm kind 2>/dev/null || true
	@echo "==> Starting cluster..."
	docker compose up -d
	@echo "==> Waiting for cluster to be ready (tailing logs)..."
	docker logs -f k8s-lab

## Attach an interactive shell to the lab container
shell:
	docker exec -it k8s-lab bash

## Run a single kubectl command from your Mac
## Usage: make k CMD="get nodes -o wide"
k:
	docker exec k8s-lab kubectl $(CMD)

## Tail container logs
logs:
	docker logs -f k8s-lab

## Stop and remove all containers and kind network
down:
	docker rm -f k8s-lab k8s-lab-control-plane k8s-lab-worker k8s-lab-worker2 2>/dev/null || true
	docker network rm kind 2>/dev/null || true
	docker compose down --remove-orphans 2>/dev/null || true

## Full clean: also removes the kubeconfig volume
clean: down
	docker volume rm k8s-kube-config 2>/dev/null || true
