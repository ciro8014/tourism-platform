#!/usr/bin/env bash
# Construye las 4 imágenes Docker y las carga directamente al cluster Kind
# (Kind no usa el registry local, hay que hacer "kind load")
set -euo pipefail

CLUSTER_NAME="tourism"
SERVICES=("auth-service" "tours-service" "bookings-service" "api-gateway")

cd "$(dirname "$0")/.."

for svc in "${SERVICES[@]}"; do
  echo ""
  echo "═══ Building tourism/${svc}:latest ═══"
  docker build -t "tourism/${svc}:latest" "./services/${svc}"
  echo "═══ Loading tourism/${svc}:latest into Kind ═══"
  kind load docker-image "tourism/${svc}:latest" --name "${CLUSTER_NAME}"
done

echo ""
echo "✅ 4 imágenes construidas y cargadas al cluster"
docker images | grep tourism/
