"""
Bookings Service - Gestión de reservas
v1.1.0 - Con retry de conexión resiliente
"""
import os
import asyncio
import logging
import httpx
from datetime import date
from contextlib import asynccontextmanager

import asyncpg
from fastapi import FastAPI, HTTPException, Header
from pydantic import BaseModel, Field

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
log = logging.getLogger("bookings-service")

DB_DSN = os.getenv("DATABASE_URL",
    "postgresql://tourism:tourism@postgres-service:5432/tourism_db")
TOURS_SERVICE_URL = os.getenv("TOURS_SERVICE_URL", "http://tours-service:8000")

pool: asyncpg.Pool | None = None


async def connect_with_retry(dsn: str, max_attempts: int = 30, delay: float = 2.0):
    for attempt in range(1, max_attempts + 1):
        try:
            log.info(f"Conectando a DB (intento {attempt}/{max_attempts})...")
            pool_ = await asyncpg.create_pool(dsn, min_size=2, max_size=10)
            log.info("✅ Conexión a DB establecida")
            return pool_
        except (OSError, asyncpg.PostgresError) as e:
            log.warning(f"Fallo DB ({type(e).__name__}): {e}")
            if attempt == max_attempts:
                raise
            await asyncio.sleep(delay)


@asynccontextmanager
async def lifespan(app: FastAPI):
    global pool
    pool = await connect_with_retry(DB_DSN)
    async with pool.acquire() as conn:
        await conn.execute("""
            CREATE TABLE IF NOT EXISTS bookings (
                id SERIAL PRIMARY KEY,
                company_id INT NOT NULL,
                tour_id INT NOT NULL,
                customer_name VARCHAR(150) NOT NULL,
                customer_email VARCHAR(150) NOT NULL,
                tour_date DATE NOT NULL,
                num_people INT NOT NULL,
                status VARCHAR(20) DEFAULT 'confirmed',
                created_at TIMESTAMP DEFAULT NOW()
            );
        """)
    yield
    await pool.close()


app = FastAPI(title="Bookings Service", version="1.1.0", lifespan=lifespan)


class BookingIn(BaseModel):
    tour_id: int
    customer_name: str
    customer_email: str
    tour_date: date
    num_people: int = Field(..., ge=1, le=50)


@app.get("/health")
async def health():
    return {"status": "ok", "service": "bookings"}


@app.post("/bookings", status_code=201)
async def create_booking(
    payload: BookingIn,
    x_company_id: int = Header(..., description="Inyectado por el API Gateway"),
):
    # Service-to-service con retry simple
    async with httpx.AsyncClient(timeout=5.0) as client:
        for attempt in range(3):
            try:
                r = await client.get(f"{TOURS_SERVICE_URL}/tours/{payload.tour_id}")
                break
            except httpx.RequestError as e:
                if attempt == 2:
                    log.error(f"tours-service unreachable: {e}")
                    raise HTTPException(503, "tours-service no disponible")
                await asyncio.sleep(0.5)
    if r.status_code == 404:
        raise HTTPException(404, "Tour no existe")
    if r.status_code != 200:
        raise HTTPException(502, "Error consultando tours-service")

    async with pool.acquire() as conn:
        row = await conn.fetchrow(
            """INSERT INTO bookings (company_id, tour_id, customer_name,
                                     customer_email, tour_date, num_people)
               VALUES ($1, $2, $3, $4, $5, $6) RETURNING *""",
            x_company_id, payload.tour_id, payload.customer_name,
            payload.customer_email, payload.tour_date, payload.num_people,
        )
    return dict(row)


@app.get("/bookings")
async def list_bookings(x_company_id: int = Header(...)):
    async with pool.acquire() as conn:
        rows = await conn.fetch(
            "SELECT * FROM bookings WHERE company_id = $1 ORDER BY id DESC",
            x_company_id,
        )
    return [dict(r) for r in rows]
