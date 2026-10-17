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

## Runtime Behaviour (normative)

### Startup Validation

- Missing required variable (`DATABASE_URL`, `TOKEN_SECRET`) → exit non-zero with clear message.
- `TOKEN_SECRET` shorter than **32 bytes** (UTF-8) → exit non-zero.
- `DB_POOL_SIZE` or `DB_ACQUIRE_TIMEOUT_MS` not a positive integer → exit non-zero.

### Startup Order

- Backend **must start and answer `GET /health`** even if Postgres is unreachable.
- DB endpoints (`/feed`, `/posts/*`) return `503 SERVICE_UNAVAILABLE` until the database is reachable.
- Process **must never exit** because of DB unavailability; must reconnect on demand.

### Pool Lifecycle

- Pool maximum = `DB_POOL_SIZE` (no required minimum, no pre-warming; connections opened on demand).
- Idle timeout and max lifetime **disabled or ≥ 1 hour** (connections not churned during a test).
- Waiting requests queue until `DB_ACQUIRE_TIMEOUT_MS`; then 503 `SERVICE_UNAVAILABLE`.

### Network

- Every backend listens on **all interfaces (`0.0.0.0`)** on `PORT`.

### Process Model

- **One process per container**. No worker-count variable (intentionally omitted).

### Prepared Statements

- Each backend's `README.md` must state its prepared-statement behaviour (driver default), since it matters for a future PgBouncer scenario.

---

## Notes

- Every backend must read these exact variable names.
- `DATABASE_URL` must be a valid `postgres://` URI (libpq-compatible).
- `TOKEN_SECRET` is used as raw UTF-8 bytes for HMAC-SHA256. Do **not** base64-decode it.
- `DB_POOL_SIZE` and `DB_ACQUIRE_TIMEOUT_MS` are integers.
- In Kubernetes, these are injected via ConfigMap/Secret; in Docker Compose via `.env` or `environment:`.
- The benchmark runner sets these per scenario/profile; backends must not hard-code values.
