# Backend-k8s-Arena

A polyglot backend benchmarking playground. The same small social-feed API is implemented in several backend stacks, packaged in Docker, deployed on Kubernetes, and load-tested with k6 to compare **throughput, latency, resource footprint, and scaling behaviour**.

It is also a learning project: containerization, orchestration, performance engineering and polyglot development, hands-on.

> **Status:** early development. See [Roadmap](#5-roadmap) and [`docs/IMPLEMENTATION_PLAN.md`](docs/IMPLEMENTATION_PLAN.md). Commands marked *(planned)* do not exist yet.

---

## 1. What is being tested

### The application

A tiny Twitter-style API backed by PostgreSQL.

| Endpoint | Description | DB work |
|---|---|---|
| `GET /feed` | The 20 newest posts, each with author and like count | 1 read query |
| `GET /posts/{id}` | One post with author and like count | 1 read query |
| `POST /posts` | Create a post as the authenticated user | 1 insert |
| `POST /posts/{id}/like` | Like a post as the authenticated user (idempotent) | 1 insert |
| `GET /health` | Liveness/readiness, no DB access | none |

Seed data (deterministic, generated in pure SQL): **50,000 users, 500,000 posts, ~2,000,000 likes** (~350 MB), so the working set mostly fits in memory.

The full contract (request/response JSON, status codes, auth, errors) lives in [`spec/API.md`](spec/API.md) *(planned)*. The canonical SQL for every endpoint lives in `spec/queries.sql` *(planned)*.

### The backends

One framework per language for v1, chosen as the "normal default production setup", not hand-tuned.

| Phase | Language | Stack |
|---|---|---|
| 1 | Python | FastAPI + Uvicorn + asyncpg |
| 1 | Go | `net/http` + pgx |
| 1 | Node.js | Express 5 + `pg` |
| later | Rust (Axum/SQLx), Java (Spring Boot), C# (ASP.NET Core), Bun, Kotlin (Ktor), PHP, Ruby, Elixir (Phoenix), Swift (Vapor), C++ | see roadmap |

### The metrics

| Category | Metrics |
|---|---|
| Latency | p50, p95, p99 (and max) per endpoint and overall |
| Throughput | Requests per second at the passing limit; raw `/feed` throughput |
| Reliability | Error rate (non-2xx, timeouts, connection failures) |
| Capacity | **Maximum simulated users that pass the criteria** (the headline number) |
| Footprint | Peak/average CPU and RAM of the app container/pod and of Postgres; image size |
| Startup/scaling | Cold start (pod created → first successful `/feed`), time-to-scale and p99 during a traffic spike |
| Bottleneck | Which resource limited the run: `app-bound`, `db-bound`, `pool-bound` or `load-generator-bound` (derived from app CPU, DB CPU and pool-wait time) |
| Efficiency | Capacity (users) per vCPU and per dollar-hour, using the hardware and price defined in the scenario |

---

## 2. How it is tested

### 2.1 What "one user" means

k6 virtual users, each with their own account and auth token, looping:

1. `GET /feed`
2. wait 3-7 s
3. `GET /posts/{id}` (a post from the feed)
4. wait 3-7 s
5. sometimes `POST /posts/{id}/like`, sometimes `POST /posts`
6. wait, repeat

That is roughly **0.1 requests per second per user**, so 1,000 users is about 100 RPS. Every result reports both users **and** actual RPS so numbers can be compared with other setups.

### 2.2 Pass / fail criteria

A load level **passes** only if all of these hold for the whole test (thresholds are configurable):

| Criterion | Default |
|---|---|
| p95 latency | <= 500 ms |
| p99 latency | <= 1000 ms |
| Error rate | <= 1 % |

### 2.3 Finding the limit (per backend)

1. **Conformance gate:** the backend must pass the shared conformance suite (status codes, auth rules, error bodies, and identical `/feed` and `/posts/{id}` response bodies against the reference) before it may be benchmarked.
2. **Warm-up:** short run at a low, fixed user count (not measured).
3. **Raw throughput test:** hammer `GET /feed` with no think time to find max RPS.
4. **Limit search:** start at a configurable user count, run **2-minute** tests, double on pass, bisect on fail (binary search).
5. **Confirmation:** the apparent maximum must also pass a **5-minute** test; if it fails, step down until one passes.
6. **Repeat** at the peak level (3 runs) and report the median; treat differences under ~10 % as noise.

### 2.4 Fairness rules

Every backend must have:

- identical endpoints, JSON, status codes and auth behaviour (enforced by the conformance suite);
- the same database schema, indexes and raw SQL, with **no ORM** and **no caching**;
- exactly **one DB query per request** (auth tokens are HMAC-signed and verified in-process, so auth costs no query);
- a DB connection pool of **10 connections per process** (with many replicas the total can exceed Postgres' `max_connections`; see scenario K1 for how this is handled);
- production builds only, access logging off in the hot path;
- identical container resource limits (see profiles below);
- the load generator on a **separate machine/node** from the system under test whenever possible.

Framework defaults are kept on purpose (e.g. a driver's default connection reset behaviour). Anything non-default that changes results is documented in the backend's own `README.md`.

### 2.5 Resource profiles

Limits are parameters, not hard-coded. Default profile `base` (to be tuned during Phase 3):

| Component | CPU | Memory |
|---|---|---|
| App container / pod | 1 vCPU | 512 MiB |
| PostgreSQL | 1 vCPU | 1 GiB |

One OS process per container; scale out by adding containers/replicas.

### 2.6 Scenarios

A **scenario** fixes four things: topology (which machines run what), hardware, database mode, and scaling. Comparing scenarios shows where the bottleneck sits and what actually relieves it. Scenarios are defined as files in `scenarios/` *(planned)* so they can be run by name.

| ID | Setup | Question it answers |
|---|---|---|
| **D1** | Docker, 1 VM, app + Postgres share it, `base` profile | Baseline single-box capacity |
| **D2** | Docker, 1 VM, bigger hardware. Two variants: extra resources to **both**, and to **Postgres only** | Does vertical scaling help, and which stacks benefit? Postgres-only shows the bottleneck shifting |
| **D3** | Docker, **2 VMs**: app on one, Postgres on the other | Effect of removing app/DB CPU contention (adds network latency) |
| **K0** | Kubernetes, **1 node**, 1 replica, same hardware as D1 | Pure Kubernetes overhead compared with Docker |
| **K1** | Kubernetes, **multi-node**, one fixed Postgres on a dedicated node, scale the **backend** (manual 1/2/4/8 replicas, then HPA) | How far the app scales before a single database caps it |
| **K2** | Kubernetes, multi-node, scale **both** backend and database | Whether scaling the database moves the ceiling |

Each scenario also supports these test types:

| Test | What it measures |
|---|---|
| Limit search (default) | Maximum passing users (section 2.3) |
| Spike (HPA scenarios) | Baseline load jumps to a multiple instantly; time-to-scale and p99/error rate during the spike |
| Cold start | Time from pod creation to first successful `/health` and first successful `/feed` |

**What "scaling the database" means.** Postgres cannot be scaled like a stateless app. The project uses three levers, introduced in this order:

1. **Vertical:** a bigger Postgres (scenario D2).
2. **Connection pooling:** with N replicas the total connections are N x 10, which can hit Postgres' default limit of 100. Scenario K1 handles this explicitly (raised `max_connections` or PgBouncer; decision recorded in the plan).
3. **Read replicas:** reads (`GET /feed`, `GET /posts/{id}`) go to replicas, writes to the primary, managed by a Kubernetes Postgres operator (CloudNativePG). This needs a second connection setting in the backends and is introduced as a new, explicit version of the API/config spec (spec v2), never silently.

**Where Kubernetes runs.** K0 runs on one node by design. K1 and K2 need several nodes (dedicated database node, 2-4 app nodes, a separate load-generator node); on a single node extra replicas share the same CPU and would measure nothing useful. Locally, `k3d` simulates multiple nodes on one machine, which is enough to verify the setup works but **not** to produce official numbers; those come from the AWS runbook.

> **Honest limitations:** results from a laptop are for development; only runs on documented, dedicated hardware are comparable. Postgres is a single primary in every scenario except K2.

### 2.7 Observability and results

- k6 results are exported as JSON per run to `results/` and, when enabled, streamed to **Prometheus**; **Grafana** dashboards show latency, RPS, errors, CPU and RAM live.
- A custom **frontend** (later phase) starts runs, shows live metrics and compares stored results across backends and modes.

---

## 3. Repository layout *(target)*

```text
backend-k8s-arena/
├── README.md
├── AGENT.md                  # rules for the AI coding agent
├── run.sh                    # single entry point
├── docs/
│   └── IMPLEMENTATION_PLAN.md
├── spec/                     # API contract + canonical SQL
├── db/                       # schema.sql, deterministic seed
├── backends/
│   ├── python/  go/  node/   # one folder per stack (Dockerfile, src, README)
├── conformance/              # shared test suite every backend must pass
├── scenarios/                # scenario definitions (D1..K2): topology, hardware, DB mode
├── loadtest/                 # k6 scripts, search algorithm
├── deploy/
│   ├── compose/              # Docker Compose mode
│   └── k8s/                  # manifests (Kustomize), HPA
├── observability/            # Prometheus + Grafana config and dashboards
├── frontend/                 # (later phase)
├── results/                  # run outputs (git-ignored except samples)
└── .github/workflows/        # CI
```

---

## 4. Running it

### Prerequisites

- Docker (with Compose v2 and buildx)
- `kubectl` and `k3d` (Kubernetes phases)
- Bash, `make`
- k6 is run through Docker, so no local install is needed

### Quick start *(planned)*

```bash
git clone https://github.com/<you>/backend-k8s-arena.git
cd backend-k8s-arena

./run.sh up --backend go              # Postgres + seed + Go backend (Docker)
./run.sh conformance --backend go     # must pass before benchmarking
./run.sh bench --backend go --mode docker --profile base
./run.sh bench --all --mode docker    # every implemented backend, one at a time
./run.sh bench --backend go --scenario D2   # run a named scenario
./run.sh down
```

Kubernetes *(planned)*:

```bash
./run.sh k8s-up                                   # create local k3d cluster
./run.sh bench --backend go --mode k8s --replicas 2
./run.sh bench --backend go --mode k8s-hpa --spike 3x
./run.sh k8s-down
```

Monitoring *(planned)*: `./run.sh observability-up`, then open Grafana at `http://localhost:3000`.

Results are written to `results/<timestamp>-<backend>-<mode>/summary.json` plus raw k6 output.

### Running on AWS *(planned)*

An optional runbook for official runs on multi-node EC2 + k3s with a separate load-generator node will be added in the AWS phase. Local-first development does not need an AWS account.

---

## 5. Roadmap

- [ ] **Phase 0** Foundation: repo, API spec, schema + seed, conformance suite, CI
- [ ] **Phase 1** Backends: Python, Go, Node.js
- [ ] **Phase 2** Load-test harness and limit-search runner
- [ ] **Phase 3** Docker scenarios (D1-D3), resource profiles, bottleneck detection and efficiency metrics
- [ ] **Phase 4** Kubernetes scenarios (K0-K2): overhead, fixed replicas, HPA, spike and cold-start tests, scaling the database
- [ ] **Phase 5** Prometheus + Grafana
- [ ] **Phase 6** Custom frontend
- [ ] **Phase 7** AWS runbook for official runs (multi-node k3s for K1/K2, two-VM Docker for D3)
- [ ] **Phase 8** More languages (Rust, Java, C#, Bun, Kotlin, PHP, Ruby, Elixir, Swift, C++), frontend updated as they land

Detailed tasks: [`docs/IMPLEMENTATION_PLAN.md`](docs/IMPLEMENTATION_PLAN.md).

## 6. Contributing / working with the coding agent

All changes go through branches and pull requests with passing CI. See [`AGENT.md`](AGENT.md).

## 7. Inspiration

The workload and methodology are modelled on the video *"I Tested 8 Programming Languages on a $12 Server"*, extended with Docker, Kubernetes, autoscaling, observability and a frontend.
