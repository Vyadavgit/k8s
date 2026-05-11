FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV KUBECONFIG=/root/.kube/config

# Install dependencies
RUN apt-get update && apt-get install -y \
    curl \
    ca-certificates \
    gnupg \
    conntrack \
    socat \
    iptables \
    iproute2 \
    net-tools \
    iputils-ping \
    dnsutils \
    tcpdump \
    vim \
    bash-completion \
    && rm -rf /var/lib/apt/lists/*

# Install Docker CLI only (daemon runs on host, socket is mounted)
RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" \
    | tee /etc/apt/sources.list.d/docker.list > /dev/null \
    && apt-get update \
    && apt-get install -y docker-ce-cli \
    && rm -rf /var/lib/apt/lists/*

# Install kubectl (arch-aware)
RUN ARCH=$(dpkg --print-architecture) \
    && KUBECTL_VERSION=$(curl -Ls https://dl.k8s.io/release/stable.txt) \
    && curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl" \
    && install kubectl /usr/local/bin/kubectl \
    && rm kubectl

# Install kind - purpose-built for running Kubernetes inside Docker
RUN ARCH=$(dpkg --print-architecture) \
    && KIND_VERSION=$(curl -Ls https://api.github.com/repos/kubernetes-sigs/kind/releases/latest | grep '"tag_name"' | cut -d'"' -f4) \
    && curl -Lo /usr/local/bin/kind "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-${ARCH}" \
    && chmod +x /usr/local/bin/kind

# Install Helm
RUN curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Shell aliases and completion
RUN echo 'alias k=kubectl' >> /root/.bashrc \
    && echo 'source <(kubectl completion bash)' >> /root/.bashrc \
    && echo 'complete -F __start_kubectl k' >> /root/.bashrc \
    && echo 'source <(kind completion bash)' >> /root/.bashrc \
    && echo 'source <(helm completion bash)' >> /root/.bashrc

RUN mkdir -p /root/.kube

COPY kind-config.yaml /kind-config.yaml
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Exposes port 6443 (Kubernetes API server) and the port range 30000-32767 (NodePort services).
# Port 6443: HTTPS API server for kubectl communication and cluster management.
# Ports 30000-32767: Reserved range for Kubernetes NodePort type services, allowing external traffic to reach services within the cluster.
EXPOSE 6443 30000-32767

ENTRYPOINT ["/entrypoint.sh"]
