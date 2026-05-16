#!/usr/bin/env bash
# Demo end-to-end idempotente
# Genera un email único cada vez para evitar colisiones, salida más limpia
set -euo pipefail

BASE="${BASE:-http://tourism.local}"
JQ=$(command -v jq || echo cat)

# Email único por ejecución (timestamp Unix)
TS=$(date +%s)
COMPANY_EMAIL="ventas+${TS}@incatravels.pe"
COMPANY_NAME="Inca Travels SAC #${TS}"

bar() { echo ""; echo "════════════════════════════════════════"; echo "$1"; echo "════════════════════════════════════════"; }

bar "1. Health check del Gateway"
curl -s "${BASE}/health" | $JQ

bar "2. Registrando una nueva empresa cliente"
echo "    name:  ${COMPANY_NAME}"
echo "    email: ${COMPANY_EMAIL}"
echo ""
RESP=$(curl -s -X POST "${BASE}/companies" \
  -H "Content-Type: application/json" \
  -d "{\"name\": \"${COMPANY_NAME}\", \"email\": \"${COMPANY_EMAIL}\"}")
echo "$RESP" | $JQ

API_KEY=$(echo "$RESP" | python3 -c "
import sys, json
data = json.load(sys.stdin)
if 'api_key' not in data:
    print('ERROR: no se obtuvo API Key. Respuesta:', data, file=sys.stderr)
    sys.exit(1)
print(data['api_key'])
")

echo ""
echo "🔑 API Key obtenida: ${API_KEY}"

bar "3. Intentando listar tours SIN API Key (debe fallar con 422)"
curl -s -o /dev/null -w "HTTP %{http_code}\n" "${BASE}/tours"

bar "4. Listando tours CON API Key (primera vez)"
curl -s "${BASE}/tours" -H "X-API-Key: ${API_KEY}" | \
  $JQ '{source: .source, total_tours: (.data | length), sample: .data[0]}'

bar "5. Listando tours nuevamente (debe venir del cache)"
curl -s "${BASE}/tours" -H "X-API-Key: ${API_KEY}" | \
  $JQ '{source: .source, total_tours: (.data | length)}'

bar "6. Creando una reserva"
echo "    (bookings-service consultará tours-service para validar el tour)"
echo ""
curl -s -X POST "${BASE}/bookings" \
  -H "Content-Type: application/json" \
  -H "X-API-Key: ${API_KEY}" \
  -d '{"tour_id": 1, "customer_name": "Maria Lopez", "customer_email": "maria@test.com",
       "tour_date": "2026-06-15", "num_people": 2}' | $JQ

bar "7. Listando las reservas de ESTA empresa (multi-tenant)"
echo "    Solo veremos las reservas creadas con esta API Key"
echo ""
curl -s "${BASE}/bookings" -H "X-API-Key: ${API_KEY}" | $JQ

echo ""
echo "✅ Demo completa"
echo "    Empresa registrada: ${COMPANY_EMAIL}"
echo "    API Key:            ${API_KEY}"