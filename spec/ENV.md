# Environment Variables

All configuration is through environment variables. No config files, no secrets in images.

---

## Required

| Variable | Description |
|----------|-------------|
| `DATABASE_URL` | PostgreSQL connection string in `postgres://` URI form. Example: `postgres://user:pass@db:5432/arena?sslmode=disable` |
| `TOKEN_SECRET` | HMAC-SHA256 key for auth tokens. **Raw UTF-8 bytes, minimum 32 bytes**. Used directly as key (not base64-decoded). |

---

## Optional (with defaults)

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT` | `8080` | HTTP listen port |
| `DB_POOL_SIZE` | `10` | Database connection pool size **per process** (fairness rule) |
| `DB_ACQUIRE_TIMEOUT_MS` | `5000` | Max time to acquire a connection from the pool. On timeout → 503 `SERVICE_UNAVAILABLE` |

---

## Notes

- Every backend must read these exact variable names.
- `DATABASE_URL` must be a valid `postgres://` URI (libpq-compatible).
- `TOKEN_SECRET` is used as raw UTF-8 bytes for HMAC-SHA256. Do **not** base64-decode it.
- `DB_POOL_SIZE` and `DB_ACQUIRE_TIMEOUT_MS` are integers.
- In Kubernetes, these are injected via ConfigMap/Secret; in Docker Compose via `.env` or `environment:`.
- The benchmark runner sets these per scenario/profile; backends must not hard-code values.
