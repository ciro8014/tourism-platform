"""
Tours Service - Catálogo de tours con caché Redis
v1.1.0 - Con retry de conexión resiliente
"""
import os
import json
import asyncio
import logging
from datetime import datetime
from contextlib import asynccontextmanager
from decimal import Decimal

import asyncpg
import redis.asyncio as redis
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
log = logging.getLogger("tours-service")

DB_DSN = os.getenv("DATABASE_URL",
    "postgresql://tourism:tourism@postgres-service:5432/tourism_db")
REDIS_URL = os.getenv("REDIS_URL", "redis://redis-service:6379")
CACHE_TTL = 60

pool: asyncpg.Pool | None = None
cache: redis.Redis | None = None


async def connect_db_with_retry(dsn: str, max_attempts: int = 30, delay: float = 2.0):
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


async def connect_redis_with_retry(url: str, max_attempts: int = 30, delay: float = 2.0):
    for attempt in range(1, max_attempts + 1):
        try:
            log.info(f"Conectando a Redis (intento {attempt}/{max_attempts})...")
            r = redis.from_url(url, decode_responses=True)
            await r.ping()
            log.info("✅ Conexión a Redis establecida")
            return r
        except (OSError, redis.RedisError) as e:
            log.warning(f"Fallo Redis ({type(e).__name__}): {e}")
            if attempt == max_attempts:
                raise
            await asyncio.sleep(delay)


@asynccontextmanager
async def lifespan(app: FastAPI):
    global pool, cache
    pool = await connect_db_with_retry(DB_DSN)
    cache = await connect_redis_with_retry(REDIS_URL)
    async with pool.acquire() as conn:
        await conn.execute("""
            CREATE TABLE IF NOT EXISTS tours (
                id SERIAL PRIMARY KEY,
                title VARCHAR(200) NOT NULL,
                location VARCHAR(150) NOT NULL,
                description TEXT,
                price_usd NUMERIC(10,2) NOT NULL,
                duration_hours INT NOT NULL,
                created_at TIMESTAMP DEFAULT NOW()
            );
        """)
        count = await conn.fetchval("SELECT COUNT(*) FROM tours")
        if count == 0:
            await conn.executemany(
                """INSERT INTO tours (title, location, description, price_usd, duration_hours)
                   VALUES ($1, $2, $3, $4, $5)""",
                [
                    ("Machu Picchu Full Day", "Cusco", "Tour guiado a la ciudadela inca", 280.00, 14),
                    ("Valle Sagrado Premium", "Cusco", "Pisac, Ollantaytambo y Chinchero", 120.00, 10),
                    ("Montaña de 7 Colores", "Cusco", "Trekking a Vinicunca", 95.00, 12),
                    ("City Tour Cusco", "Cusco", "Sacsayhuamán, Qenqo, Tambomachay", 45.00, 5),
                    ("Laguna Humantay", "Cusco", "Trekking a la laguna turquesa", 75.00, 9),
                ],
            )
    yield
    await pool.close()
    await cache.aclose()


app = FastAPI(title="Tours Service", version="1.1.0", lifespan=lifespan)


class TourIn(BaseModel):
    title: str
    location: str
    description: str | None = None
    price_usd: Decimal = Field(..., ge=0)
    duration_hours: int = Field(..., ge=1)


class TourOut(TourIn):
    id: int
    created_at: datetime


@app.get("/health")
async def health():
    return {"status": "ok", "service": "tours"}


@app.get("/tours")
async def list_tours():
    cached = await cache.get("tours:all")
    if cached:
        return {"source": "cache", "data": json.loads(cached)}

    async with pool.acquire() as conn:
        rows = await conn.fetch("SELECT * FROM tours ORDER BY id")
    data = [
        {**dict(r), "price_usd": float(r["price_usd"]), "created_at": r["created_at"].isoformat()}
        for r in rows
    ]
    await cache.setex("tours:all", CACHE_TTL, json.dumps(data))
    return {"source": "database", "data": data}


@app.get("/tours/{tour_id}", response_model=TourOut)
async def get_tour(tour_id: int):
    async with pool.acquire() as conn:
        row = await conn.fetchrow("SELECT * FROM tours WHERE id = $1", tour_id)
    if not row:
        raise HTTPException(404, "Tour no encontrado")
    return dict(row)


@app.post("/tours", response_model=TourOut, status_code=201)
async def create_tour(payload: TourIn):
    async with pool.acquire() as conn:
        row = await conn.fetchrow(
            """INSERT INTO tours (title, location, description, price_usd, duration_hours)
               VALUES ($1, $2, $3, $4, $5) RETURNING *""",
            payload.title, payload.location, payload.description,
            payload.price_usd, payload.duration_hours,
        )
    await cache.delete("tours:all")
    return dict(row)
