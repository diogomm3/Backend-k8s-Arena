# API Contract

**Version:** 1.0  
**Status:** Stable (frozen for Phase 1 backends)

---

## 1. Endpoints

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `GET` | `/health` | No | Liveness/readiness probe |
| `GET` | `/feed` | Yes | 20 newest posts with author and like count |
| `GET` | `/posts/{id}` | Yes | One post with author and like count |
| `POST` | `/posts` | Yes | Create a post as the authenticated user |
| `POST` | `/posts/{id}/like` | Yes | Like a post (idempotent) |

All endpoints return `Content-Type: application/json`.  
Error responses use the error format in §4.

---

## 2. Authentication

### 2.1 Token Format

```
<user_id>.<base64url_signature>
```

- `user_id`: Canonical decimal string — **digits only, no leading zeros, range 1..2147483647**.
- `signature`: `base64url(HMAC_SHA256(TOKEN_SECRET, user_id))` where `TOKEN_SECRET` is the raw UTF-8 bytes of the configured secret (minimum 32 bytes). No padding (`=` stripped).
- Header: `Authorization: Bearer <token>` — **exactly this format**. Anything else → `INVALID_TOKEN`.

### 2.2 Verification Algorithm (in-process, no DB)

```python
def verify(token: str, secret: str) -> int | None:
    # 1. Split on '.'
    parts = token.split('.')
    if len(parts) != 2:
        return None
    user_id_str, sig_b64url = parts

    # 2. Validate user_id format (canonical decimal)
    if not user_id_str.isdigit() or user_id_str.startswith('0'):
        return None
    user_id = int(user_id_str)
    if not (1 <= user_id <= 2147483647):
        return None

    # 3. Compute expected signature over the EXACT user_id string
    expected = base64.urlsafe_b64encode(
        hmac.new(secret.encode('utf-8'), user_id_str.encode('utf-8'), hashlib.sha256).digest()
    ).decode().rstrip('=')

    # 4. Constant-time compare on ENCODED strings (rejects non-canonical base64url)
    if not hmac.compare_digest(expected, sig_b64url):
        return None

    return user_id
```

Tokens **do not expire**. A token for a non-existent `user_id` is out of contract (conformance does not test it); backends must not crash (map FK violations on write to 500).

### 2.3 Test Vectors

**Secret (32 bytes raw UTF-8):** `test-secret-min-32-bytes-long!!!`

Generated with Python and verified with OpenSSL:

```bash
# Python
python3 -c "
import hmac, hashlib, base64
key = b'test-secret-min-32-bytes-long!!!'
for uid in [1, 42, 50000]:
    msg = str(uid).encode()
    sig = base64.urlsafe_b64encode(hmac.new(key, msg, hashlib.sha256).digest()).decode().rstrip('=')
    print(f'{uid}.{sig}')
"

# OpenSSL
SECRET="test-secret-min-32-bytes-long!!!"
for uid in 1 42 50000; do
  echo -n "$uid" | openssl dgst -sha256 -hmac "$SECRET" -binary | base64 | tr '+/' '-_' | tr -d '='
done
```

| Description | Token |
|-------------|-------|
| Valid (user 1) | `1.gcX1luKB6Q-1tVaOPeoHhClcS0yahfmTZDJLzo9MlFQ` |
| Valid (user 42) | `42.YwNBhb1bsMu0eITkUgdiyYnrbw333GRFbOGQ8bEGNDc` |
| Valid (user 50000) | `50000.oKD8K9FEMr82c5Jmokec5unmgoiDnICCKVN_xx2G83E` |
| Tampered (last char flipped) | `42.YwNBhb1bsMu0eITkUgdiyYnrbw333GRFbOGQ8bEGNDA` |
| Non-canonical (padding `=`) | `42.YwNBhb1bsMu0eITkUgdiyYnrbw333GRFbOGQ8bEGNDc=` |
| Non-canonical (alt char `d` decodes to same bytes) | `42.YwNBhb1bsMu0eITkUgdiyYnrbw333GRFbOGQ8bEGNDd` |

**Conformance must reject both non-canonical vectors** (backends compare encoded strings in constant time, do not decode).

---

## 3. Success Responses

### 3.1 `GET /health` — 200

```json
{ "status": "ok" }
```

### 3.2 `GET /feed` — 200

Array of post objects, **newest first** (`created_at DESC, id DESC` tie-break). Exactly 20 items (or fewer if seed has fewer).

```json
[
  {
    "id": 1,
    "user_id": 42,
    "username": "alice",
    "content": "hello world",
    "created_at": "2026-10-17T12:34:56.789Z",
    "like_count": 12
  }
]
```

### 3.3 `GET /posts/{id}` — 200

Single post object (same shape as feed item).

```json
{
  "id": 1,
  "user_id": 42,
  "username": "alice",
  "content": "hello world",
  "created_at": "2026-10-17T12:34:56.789Z",
  "like_count": 12
}
```

### 3.4 `POST /posts` — 201

Request body:

```json
{ "content": "new post content" }
```

Response (created post with `like_count: 0`):

```json
{
  "id": 500001,
  "user_id": 42,
  "username": "alice",
  "content": "new post content",
  "created_at": "2026-10-17T12:34:56.789Z",
  "like_count": 0
}
```

### 3.5 `POST /posts/{id}/like` — 200

Request body: **ignored** (may be empty or omitted).  
`Content-Type`: **ignored**.

Response (minimal write response):

```json
{ "post_id": 1, "like_count": 13 }
```

---

## 4. Error Format

All error responses (including 404, 405, 500, 503) have `Content-Type: application/json` and body:

```json
{ "error": { "code": "ERROR_CODE", "message": "human-readable hint" } }
```

`code` is machine-readable; `message` is a hint only and may change.

---

## 5. Status Codes & Precedence

Precedence order (first match wins):

| Step | Condition | Code | Error `code` |
|------|-----------|------|--------------|
| 1 | Unknown route | 404 | `NOT_FOUND` |
| 1 | Wrong HTTP method | 405 | `METHOD_NOT_ALLOWED` |
| 2 | Missing `Authorization` header | 401 | `UNAUTHENTICATED` |
| 2 | Malformed token (wrong format, bad base64url, non-canonical base64url, constant-time mismatch, invalid user_id format) | 401 | `INVALID_TOKEN` |
| 3 | `post_id` not digits / leading zeros / out of range (1..2147483647) | 400 | `INVALID_ID` |
| 4 | `Content-Type` not `application/json` (case-insensitive, optional `; charset=utf-8` suffix) — **only for `POST /posts`** | 400 | `INVALID_BODY` |
| 4 | Body > 16 KB | 413 | `PAYLOAD_TOO_LARGE` |
| 4 | Invalid JSON syntax | 400 | `INVALID_BODY` |
| 4 | JSON root not an object | 400 | `VALIDATION_ERROR` |
| 4 | Missing `content` field | 400 | `VALIDATION_ERROR` |
| 4 | Extra fields in body | 400 | `VALIDATION_ERROR` |
| 4 | Wrong JSON type for `content` (not string) | 400 | `VALIDATION_ERROR` |
| 4 | `content` empty / whitespace-only / > 280 Unicode code points (after JSON decode) / contains U+0000 | 400 | `VALIDATION_ERROR` |
| 5 | Post not found | 404 | `NOT_FOUND` |
| 5 | Token user_id not found in DB (FK violation on write) | 500 | `INTERNAL` |
| 5 | Pool acquire timeout / database unreachable | 503 | `SERVICE_UNAVAILABLE` |
| 5 | Any other DB error | 500 | `INTERNAL` |

**Notes:**
- `GET /feed`, `GET /posts/{id}`, `POST /posts/{id}/like` **ignore request body and Content-Type**.
- All endpoints return `Content-Type: application/json` (errors included).

---

## 6. Validation Rules (Detail)

### 6.1 `post_id` (path parameter)

- Digits only, no leading zeros, integer range 1..2147483647.
- Otherwise → 400 `INVALID_ID`.

### 6.2 `POST /posts` Body

| Rule | Error |
|------|-------|
| `Content-Type` must be `application/json` (case-insensitive, `; charset=utf-8` allowed) | 400 `INVALID_BODY` |
| Body size ≤ 16 KB | 413 `PAYLOAD_TOO_LARGE` |
| Valid JSON | 400 `INVALID_BODY` |
| Root is object | 400 `VALIDATION_ERROR` |
| Exactly one field: `content` (string) | 400 `VALIDATION_ERROR` |
| `content` non-empty after trim, ≤ 280 Unicode code points, no U+0000 | 400 `VALIDATION_ERROR` |

Code points are counted **after JSON decoding**.

### 6.3 `POST /posts/{id}/like` Body

Ignored. No validation.

---

## 7. Like Semantics

- **Idempotent**: first like inserts a row in `likes`; repeat likes are no-ops (`ON CONFLICT DO NOTHING`).
- Response **always** returns current `like_count` for that post: `{ "post_id": N, "like_count": M }`.
- First like → `M = previous + 1`.
- Repeat like → `M` unchanged (snapshot value).
- Unknown post → query returns 0 rows → 404 `NOT_FOUND`, nothing inserted.
- **Concurrency note**: Under concurrent likes the returned `like_count` reflects the statement's snapshot plus its own insert and may omit a simultaneous insert by another request (acceptable, not tested).

---

## 8. Timestamp Format

All `created_at` fields are RFC3339 / ISO 8601 with **fixed 3 fractional digits** and trailing `Z`:

```
YYYY-MM-DDTHH:MM:SS.mmmZ
```

Generated in SQL by:

```sql
to_char(created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
```

This ensures every backend emits an identical string regardless of driver formatting.

---

## 9. ID Types

- All IDs (`id`, `user_id`, `post_id`, `like_count`) are **32-bit signed integers** (`int4` in Postgres, `serial`/`integer` columns).
- **No `bigint` reaches any response** — every `COUNT(*)` is cast to `::int` in the canonical queries.
- Range fits seed: users 1..50000, posts 1..500000.

---

## 10. Deterministic Ordering

- `/feed`: `ORDER BY created_at DESC, id DESC` (tie-break by `id`).
- Seed timestamps are generated so that tie-breaks are deterministic and stable across runs.
- Conformance compares `/feed` and `/posts/{id}` response bodies as **parsed JSON** (key order and whitespace not significant; array order **is** significant).

---

## 11. Schema Appendix (Logical)

| Table | Columns | Constraints | Indexes |
|-------|---------|-------------|---------|
| `users` | `id serial PK`, `username text UNIQUE NOT NULL`, `created_at timestamptz DEFAULT now()` | PK, UNIQUE | — |
| `posts` | `id serial PK`, `user_id int NOT NULL REFERENCES users(id)`, `content text NOT NULL`, `created_at timestamptz DEFAULT now()` | PK, FK | `(created_at DESC, id DESC)` for `/feed` |
| `likes` | `post_id int NOT NULL REFERENCES posts(id)`, `user_id int NOT NULL REFERENCES users(id)`, `created_at timestamptz DEFAULT now()` | **PK(`post_id`,`user_id`) in this order**, FKs | PK covers `post_id` lookups |

**The `likes` primary key must be `(post_id, user_id)` in that column order** — the canonical count queries depend on it.

---

## 12. Canonical SQL

See `spec/queries.sql` — exactly one statement per endpoint, with `-- name:` comments and positional parameters `$1`, `$2…`.