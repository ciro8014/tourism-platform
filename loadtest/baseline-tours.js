import http from 'k6/http';
import { check, sleep } from 'k6';
import { Trend, Rate } from 'k6/metrics';

// URL base del Ingress. Se puede sobreescribir con:  k6 run -e BASE=http://otra.local ...
const BASE = __ENV.BASE || 'http://tourism.local';

// Métricas personalizadas para reportar en el informe
const toursLatency = new Trend('tours_latency', true); // true => se trata como tiempo (ms)
const errorRate = new Rate('errors');

export const options = {
  // Perfil de carga: rampa -> sostenido -> bajada (~1m45s en total)
  stages: [
    { duration: '30s', target: 20 }, // sube a 20 usuarios virtuales
    { duration: '60s', target: 20 }, // mantiene 20 VUs (carga estable)
    { duration: '15s', target: 0 },  // baja a 0
  ],
  // Umbrales: si no se cumplen, k6 marca el test como fallido (pero igual reporta los números)
  thresholds: {
    http_req_duration: ['p(95)<500', 'p(99)<1000'], // ms
    errors: ['rate<0.01'],                            // < 1% de errores
  },
};

// setup(): se ejecuta UNA sola vez antes de la carga.
// Registra una empresa cliente y devuelve su API Key a todos los VUs.
export function setup() {
  const ts = Date.now();
  const payload = JSON.stringify({
    name: `LoadTest SAC #${ts}`,
    email: `loadtest+${ts}@incatravels.pe`,
  });

  const res = http.post(`${BASE}/companies`, payload, {
    headers: { 'Content-Type': 'application/json' },
  });

  const apiKey = res.json('api_key');
  if (!apiKey) {
    throw new Error(`No se obtuvo API Key (HTTP ${res.status}): ${res.body}`);
  }
  console.log(`Empresa de prueba registrada, API Key: ${apiKey}`);
  return { apiKey };
}

// VU principal: lista tours con la API Key (camino de lectura cacheado en Redis).
export default function (data) {
  const res = http.get(`${BASE}/tours`, {
    headers: { 'X-API-Key': data.apiKey },
    tags: { name: 'GET /tours' },
  });

  const ok = check(res, {
    'status 200': (r) => r.status === 200,
    'trae data': (r) => r.json('data') !== undefined,
  });

  toursLatency.add(res.timings.duration);
  errorRate.add(!ok);

  sleep(0.5); // pausa entre peticiones por VU
}
