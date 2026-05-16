#!/usr/bin/env bash
# Aplica los fixes de retry a los 4 servicios:
# 1. Reemplaza los main.py
# 2. Reconstruye las imágenes Docker
# 3. Las recarga al cluster
# 4. Fuerza un rollout para que los pods tomen la nueva versión
set -euo pipefail

cd "$(dirname "$0")/.."

CLUSTER_NAME="tourism"
SERVICES=("auth-service" "tours-service" "bookings-service" "api-gateway")

echo "════════════════════════════════════════"
echo "  Aplicando fix de retry a los servicios"
echo "════════════════════════════════════════"

for svc in "${SERVICES[@]}"; do
  echo ""
  echo "═══ ${svc} ═══"

  # Backup del main.py original (por si quieres comparar)
  if [ ! -f "services/${svc}/main.py.bak" ]; then
    cp "services/${svc}/main.py" "services/${svc}/main.py.bak"
    echo "✓ Backup guardado en services/${svc}/main.py.bak"
  fi

  # Reemplazar con la versión nueva
  cp "${svc}/main.py" "services/${svc}/main.py"
  echo "✓ main.py reemplazado con versión 1.1.0"

  # Reconstruir imagen con un tag NUEVO para forzar a Kubernetes a actualizar
  docker build -t "tourism/${svc}:1.1.0" "./services/${svc}"
  docker tag "tourism/${svc}:1.1.0" "tourism/${svc}:latest"
  echo "✓ Imagen reconstruida"

  # Cargar al cluster Kind
  kind load docker-image "tourism/${svc}:1.1.0" --name "${CLUSTER_NAME}"
  kind load docker-image "tourism/${svc}:latest" --name "${CLUSTER_NAME}"
  echo "✓ Imagen cargada al cluster"

  # Forzar rollout (Kubernetes recreará los pods con la nueva imagen)
  kubectl -n tourism rollout restart deployment/${svc}
  echo "✓ Rollout disparado"
done

echo ""
echo "════════════════════════════════════════"
echo "  Esperando a que todos los pods estén ready..."
echo "════════════════════════════════════════"

for svc in "${SERVICES[@]}"; do
  kubectl -n tourism rollout status deployment/${svc} --timeout=180s
done

echo ""
echo "✅ Fix aplicado. Estado actual:"
kubectl -n tourism get pods

echo ""
echo "💡 Verifica que ya no haya reinicios anómalos:"
echo "   kubectl -n tourism get pods"
echo "   (la columna RESTARTS debería quedarse en 0)"
