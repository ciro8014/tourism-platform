import http from 'k6/http';
import { check } from 'k6';

// Carga pesada para FORZAR el escalado del api-gateway.
// Sin sleep: cada VU dispara peticiones de corrido para maximizar RPS.
const BASE = __ENV.BASE || 'http://tourism.local';

export const options = {
  scenarios: {
    ramp_load: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '30s', target: 40 },  // sube a 40 VUs
        { duration: '3m',  target: 40 },   // sostiene 3 min (deja a KEDA reaccionar)
        { duration: '30s', target: 0 },    // baja
      ],
    },
  },
};

// Registra una empresa una sola vez y reparte la API Key a los VUs.
export function setup() {
  const ts = Date.now();
  const res = http.post(`${BASE}/companies`, JSON.stringify({
    name: `ScaleTest SAC #${ts}`,
    email: `scale+${ts}@incatravels.pe`,
  }), { headers: { 'Content-Type': 'application/json' } });

  const apiKey = res.json('api_key');
  if (!apiKey) {
    throw new Error(`No se obtuvo API Key (HTTP ${res.status}): ${res.body}`);
  }
  return { apiKey };
}

export default function (data) {
  const res = http.get(`${BASE}/tours`, {
    headers: { 'X-API-Key': data.apiKey },
  });
  check(res, { 'status 200': (r) => r.status === 200 });
  // sin sleep a proposito
}
