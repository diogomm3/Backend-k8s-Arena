# Backend Implementations

One folder per stack (T10-T12, T8x):

- `python/` — FastAPI + Uvicorn + asyncpg (T10)
- `go/` — net/http + pgx (T11)
- `node/` — Express 5 + pg (T12)

Each backend contains:
- Source code
- Multi-stage `Dockerfile` (linux/amd64 + linux/arm64, non-root, HEALTHCHECK)
- `README.md` — Stack, versions, process model, non-default settings