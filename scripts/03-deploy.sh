#!/usr/bin/env bash
# Aplica todos los manifests en el orden correcto
set -euo pipefail

cd "$(dirname "$0")/.."

echo "[1/4] Namespace, ConfigMap y Secrets..."
kubectl apply -f k8s/base/

echo "[2/4] Bases de datos (PostgreSQL + Redis)..."
kubectl apply -f k8s/databases/
echo "    Esperando a PostgreSQL..."
kubectl -n tourism wait --for=condition=ready pod -l app=postgres --timeout=120s
echo "    Esperando a Redis..."
kubectl -n tourism wait --for=condition=ready pod -l app=redis --timeout=60s

echo "[3/4] Microservicios..."
kubectl apply -f k8s/services/
kubectl -n tourism wait --for=condition=ready pod -l app=auth-service --timeout=120s
kubectl -n tourism wait --for=condition=ready pod -l app=tours-service --timeout=120s
kubectl -n tourism wait --for=condition=ready pod -l app=bookings-service --timeout=120s
kubectl -n tourism wait --for=condition=ready pod -l app=api-gateway --timeout=120s

echo "[4/4] Ingress..."
kubectl apply -f k8s/ingress/

echo ""
echo "✅ Despliegue completo"
echo ""
kubectl -n tourism get pods
echo ""
kubectl -n tourism get svc
echo ""
echo "👉 Prueba con: curl http://tourism.local/"
