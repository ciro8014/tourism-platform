"""
Auth Service - Gestión de empresas clientes y API Keys
v1.1.0 - Con retry de conexión resiliente a fallos de DNS/DB al arranque
"""
import os
import secrets
import hashlib
import asyncio
import logging
from datetime import datetime
from contextlib import asynccontextmanager

import asyncpg
from fastapi import FastAPI, HTTPException, Header
from pydantic import BaseModel, EmailStr

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
log = logging.getLogger("auth-service")

DB_DSN = os.getenv(
    "DATABASE_URL",
    "postgresql://tourism:tourism@postgres-service:5432/tourism_db",
)

pool: asyncpg.Pool | None = None


async def connect_with_retry(dsn: str, max_attempts: int = 30, delay: float = 2.0):
    """Reintenta conexión a DB. Resistente a DNS lookup failures al arranque."""
    for attempt in range(1, max_attempts + 1):
        try:
            log.info(f"Conectando a DB (intento {attempt}/{max_attempts})...")
            pool_ = await asyncpg.create_pool(dsn, min_size=2, max_size=10)
            log.info("✅ Conexión a DB establecida")
            return pool_
        except (OSError, asyncpg.PostgresError) as e:
            log.warning(f"Fallo conexión ({type(e).__name__}): {e}")
            if attempt == max_attempts:
                log.error("Se agotaron los intentos de conexión a DB")
                raise
            await asyncio.sleep(delay)


@asynccontextmanager
async def lifespan(app: FastAPI):
    global pool
    pool = await connect_with_retry(DB_DSN)
    async with pool.acquire() as conn:
        await conn.execute("""
            CREATE TABLE IF NOT EXISTS companies (
                id SERIAL PRIMARY KEY,
                name VARCHAR(150) NOT NULL,
                email VARCHAR(150) UNIQUE NOT NULL,
                api_key_hash VARCHAR(64) UNIQUE NOT NULL,
                created_at TIMESTAMP DEFAULT NOW()
            );
        """)
    yield
    await pool.close()


app = FastAPI(title="Auth Service", version="1.1.0", lifespan=lifespan)


class CompanyCreate(BaseModel):
    name: str
    email: EmailStr


class CompanyOut(BaseModel):
    id: int
    name: str
    email: str
    api_key: str
    created_at: datetime


def hash_key(key: str) -> str:
    return hashlib.sha256(key.encode()).hexdigest()


@app.get("/health")
async def health():
    return {"status": "ok", "service": "auth"}


@app.post("/companies", response_model=CompanyOut, status_code=201)
async def create_company(payload: CompanyCreate):
    raw_key = f"tk_{secrets.token_urlsafe(32)}"
    key_hash = hash_key(raw_key)
    async with pool.acquire() as conn:
        try:
            row = await conn.fetchrow(
                """INSERT INTO companies (name, email, api_key_hash)
                   VALUES ($1, $2, $3)
                   RETURNING id, name, email, created_at""",
                payload.name, payload.email, key_hash,
            )
        except asyncpg.UniqueViolationError:
            raise HTTPException(409, "Email ya registrado")
    return CompanyOut(**dict(row), api_key=raw_key)


@app.get("/validate")
async def validate_key(x_api_key: str = Header(...)):
    async with pool.acquire() as conn:
        row = await conn.fetchrow(
            "SELECT id, name, email FROM companies WHERE api_key_hash = $1",
            hash_key(x_api_key),
        )
    if not row:
        raise HTTPException(401, "API Key inválida")
    return {"valid": True, "company_id": row["id"], "name": row["name"]}


@app.get("/companies/me")
async def me(x_api_key: str = Header(...)):
    async with pool.acquire() as conn:
        row = await conn.fetchrow(
            "SELECT id, name, email, created_at FROM companies WHERE api_key_hash = $1",
            hash_key(x_api_key),
        )
    if not row:
        raise HTTPException(401, "API Key inválida")
    return dict(row)
