"""
API Gateway - Punto único de entrada
v1.1.0 - Con retry en service-to-service calls
"""
import os
import asyncio
import logging
import httpx
from fastapi import FastAPI, HTTPException, Header, Request
from fastapi.responses import JSONResponse

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
log = logging.getLogger("api-gateway")

AUTH_URL = os.getenv("AUTH_SERVICE_URL", "http://auth-service:8000")
TOURS_URL = os.getenv("TOURS_SERVICE_URL", "http://tours-service:8000")
BOOKINGS_URL = os.getenv("BOOKINGS_SERVICE_URL", "http://bookings-service:8000")

app = FastAPI(
    title="Tourism Platform API Gateway",
    description="Punto de entrada para empresas que consumen el catálogo de tours y gestionan reservas",
    version="1.1.0",
)


@app.get("/health")
async def health():
    return {"status": "ok", "service": "gateway"}


@app.get("/")
async def root():
    return {
        "service": "Tourism Platform Gateway",
        "version": "1.1.0",
        "docs": "/docs",
        "endpoints": {
            "register_company": "POST /companies",
            "list_tours": "GET /tours (requiere X-API-Key)",
            "create_booking": "POST /bookings (requiere X-API-Key)",
            "list_bookings": "GET /bookings (requiere X-API-Key)",
        },
    }


async def fetch_with_retry(client: httpx.AsyncClient, method: str, url: str, **kwargs):
    """Llamada HTTP con retry exponencial (3 intentos)."""
    last_err = None
    for attempt in range(3):
        try:
            return await client.request(method, url, **kwargs)
        except httpx.RequestError as e:
            last_err = e
            log.warning(f"Intento {attempt+1}/3 fallido para {url}: {e}")
            if attempt < 2:
                await asyncio.sleep(0.3 * (2 ** attempt))
    raise HTTPException(503, f"Servicio downstream no disponible: {last_err}")


async def validate_key(api_key: str) -> dict:
    async with httpx.AsyncClient(timeout=5.0) as client:
        r = await fetch_with_retry(client, "GET", f"{AUTH_URL}/validate",
                                    headers={"X-API-Key": api_key})
    if r.status_code == 401:
        raise HTTPException(401, "API Key inválida o no provista")
    if r.status_code != 200:
        raise HTTPException(502, "Error en auth-service")
    return r.json()


@app.post("/companies", status_code=201)
async def register_company(request: Request):
    body = await request.json()
    async with httpx.AsyncClient(timeout=5.0) as client:
        r = await fetch_with_retry(client, "POST", f"{AUTH_URL}/companies", json=body)
    return JSONResponse(status_code=r.status_code, content=r.json())


@app.get("/tours")
async def list_tours(x_api_key: str = Header(...)):
    await validate_key(x_api_key)
    async with httpx.AsyncClient(timeout=5.0) as client:
        r = await fetch_with_retry(client, "GET", f"{TOURS_URL}/tours")
    return JSONResponse(status_code=r.status_code, content=r.json())


@app.get("/tours/{tour_id}")
async def get_tour(tour_id: int, x_api_key: str = Header(...)):
    await validate_key(x_api_key)
    async with httpx.AsyncClient(timeout=5.0) as client:
        r = await fetch_with_retry(client, "GET", f"{TOURS_URL}/tours/{tour_id}")
    return JSONResponse(status_code=r.status_code, content=r.json())


@app.post("/bookings", status_code=201)
async def create_booking(request: Request, x_api_key: str = Header(...)):
    company = await validate_key(x_api_key)
    body = await request.json()
    async with httpx.AsyncClient(timeout=5.0) as client:
        r = await fetch_with_retry(client, "POST", f"{BOOKINGS_URL}/bookings",
                                    json=body,
                                    headers={"X-Company-Id": str(company["company_id"])})
    return JSONResponse(status_code=r.status_code, content=r.json())


@app.get("/bookings")
async def list_bookings(x_api_key: str = Header(...)):
    company = await validate_key(x_api_key)
    async with httpx.AsyncClient(timeout=5.0) as client:
        r = await fetch_with_retry(client, "GET", f"{BOOKINGS_URL}/bookings",
                                    headers={"X-Company-Id": str(company["company_id"])})
    return JSONResponse(status_code=r.status_code, content=r.json())
