#!/usr/bin/env bash
# Setup completo del cluster Kind con soporte de Ingress NGINX
set -euo pipefail

CLUSTER_NAME="tourism"

echo "[1/4] Creando cluster Kind..."
cat <<EOF | kind create cluster --name "${CLUSTER_NAME}" --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
  extraPortMappings:
  - containerPort: 80
    hostPort: 80
    protocol: TCP
  - containerPort: 443
    hostPort: 443
    protocol: TCP
- role: worker
- role: worker
EOF

echo "[2/4] Instalando Ingress NGINX..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

echo "[3/4] Esperando a que Ingress NGINX esté listo..."
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=180s

echo "[4/4] Cluster listo. Nodos:"
kubectl get nodes
echo ""
echo "✅ Cluster '${CLUSTER_NAME}' creado con Ingress NGINX"
echo "Recuerda agregar a /etc/hosts:  127.0.0.1  tourism.local"
