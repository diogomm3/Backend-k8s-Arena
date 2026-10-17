# Implementation Plan

Ordered task list for Backend-k8s-Arena. Each task is one branch, one PR, and is only started after the human approves the agent's short plan for it (see `AGENT.md`).

**Legend:** `[ ]` todo, `[~]` in progress, `[x]` merged to `main`.
**Branch naming:** `feat/<task-id>-<slug>` (e.g. `feat/t10-backend-python`).
**Every task ends with:** CI green, README/docs updated if behaviour changed, feedback report posted.

---

## Phase 0: Foundation

### [x] T00 Repo scaffold
- Branch: `feat/t00-scaffold`
- Already in the repo (do not recreate): `LICENSE` (Apache-2.0), `README.md`, `AGENT.md`, `docs/IMPLEMENTATION_PLAN.md`.
- Create the rest of the folder layout from the README (including `scenarios/`), with `.gitkeep` or short placeholder READMEs where needed, `.gitignore`, `.editorconfig`, `.dockerignore` template, PR template, issue templates.
- Placeholder `run.sh` with `help` only.
- **Done when:** repo cloneable, `./run.sh help` works, layout matches README.

### [ ] T01 CI skeleton
- Branch: `feat/t01-ci`
- GitHub Actions: markdown lint, `shellcheck` for scripts, YAML lint, a path-filtered matrix job template that later tasks extend per backend.
- Branch protection recommendation documented (require PR + green CI).
- **Done when:** a PR triggers the workflows and they pass on the scaffold.

### [ ] T02 API contract and canonical SQL
- Branch: `feat/t02-spec`
- `spec/API.md`: all endpoints, JSON shapes, status codes, auth scheme (HMAC-signed token `<user_id>.<signature>`, secret via `TOKEN_SECRET`), error format, validation rules (post length etc.), idempotent like behaviour.
- `spec/queries.sql`: exactly one canonical statement per endpoint.
- `spec/ENV.md`: required env vars (`PORT`, `DATABASE_URL`, `DB_POOL_SIZE=10`, `TOKEN_SECRET`).
- **Done when:** the human approves the spec; nothing else is built before this is signed off.

### [ ] T03 Database schema and deterministic seed
- Branch: `feat/t03-database`
- `db/schema.sql` (users, posts, likes, all indexes needed by the canonical queries).
- Seed in pure SQL (`generate_series`, fixed random seed): 50k users, 500k posts, ~2M likes, no duplicate likes.
- Postgres container config for the benchmark (documented settings, e.g. `shared_buffers`), a `./run.sh db-up|db-seed|db-reset` set of commands.
- Seed row-count and index sanity check script.
- **Done when:** a fresh seed produces the stated counts, DB size is roughly 350 MB, and the canonical queries use their indexes (`EXPLAIN` output saved in docs).

### [ ] T04 Conformance suite
- Branch: `feat/t04-conformance`
- Black-box suite runnable against any base URL (about 40 checks): status codes, auth rules, validation, error bodies, idempotent like, `/feed` and `/posts/{id}` body comparison against a reference snapshot.
- Reference snapshot generated once from the seed (documented how to regenerate).
- Runs through Docker; `./run.sh conformance --backend <name>`.
- **Done when:** suite is runnable and has been verified against a stub/mock server that implements the spec.

---

## Phase 1: First backends

Each backend task includes: implementation, multi-stage `Dockerfile` (small, non-root, pinned versions, `linux/amd64` + `linux/arm64`), backend `README.md` (stack, versions, process model, non-default settings), CI job (build image + run conformance against Postgres with a small seed), and a check that its SQL matches `spec/queries.sql`.

### [ ] T10 Backend: Python (FastAPI + Uvicorn + asyncpg)
- Branch: `feat/t10-backend-python`
- **Done when:** conformance 100 % green locally and in CI; image builds for both architectures; pool size 10 per process.

### [ ] T11 Backend: Go (`net/http` + pgx)
- Branch: `feat/t11-backend-go`
- **Done when:** same criteria as T10.

### [ ] T12 Backend: Node.js (Express 5 + pg)
- Branch: `feat/t12-backend-node`
- **Done when:** same criteria as T10.

---

## Phase 2: Load-test harness

### [ ] T20 k6 user-journey script
- Branch: `feat/t20-k6-journey`
- Realistic user loop (feed, wait 3-7 s, post, like/create), per-user tokens generated with the shared secret, configurable thresholds (p95/p99/error rate), JSON output.
- **Done when:** a 1-minute smoke run against each of the 3 backends passes thresholds at a low user count.

### [ ] T21 Raw throughput + warm-up scripts
- Branch: `feat/t21-k6-throughput`
- `/feed` max-RPS test and warm-up scenario.

### [ ] T22 Limit-search runner
- Branch: `feat/t22-runner`
- Automates: warm-up, raw throughput, doubling + bisection search (2-min steps), 5-min confirmation with step-down, 3 repeats at peak, median reporting.
- Writes `results/<run>/summary.json` with a documented schema (users, RPS, p50/p95/p99, error rate, resource usage, environment info: CPU model, cores, RAM, versions).
- `./run.sh bench --backend <name> --mode docker`.
- **Done when:** a full search completes unattended for one backend and produces a valid summary.

---

## Phase 3: Docker scenarios (D1-D3)

### [ ] T30 Docker Compose stack and resource profiles
- Branch: `feat/t30-compose`
- `deploy/compose/` with Postgres + one selectable backend, hard CPU/memory limits driven by a profile file (`base`, easy to add more; separate limits for app and Postgres), health checks, only one backend running at a time.
- Resource sampling (CPU/RAM of app and Postgres, plus pool-wait where the backend exposes it) written into the results.
- **Done when:** `./run.sh bench --all --mode docker` benchmarks all three backends end to end on one machine and tears everything down.

### [ ] T31 Scenario definitions (D1, D2)
- Branch: `feat/t31-scenarios`
- `scenarios/*.yaml` format: topology, hardware per component (CPU/RAM), DB mode, scaling, price per hour (optional, for efficiency metrics). Defines D1 and D2 (both variants: resources to both, resources to Postgres only).
- `./run.sh bench --backend <name> --scenario <ID>`; scenario info is copied into each `summary.json`.
- **Done when:** D1 and D2 (both variants) run by name and results are tagged with the scenario.

### [ ] T32 Two-host Docker scenario (D3)
- Branch: `feat/t32-two-host`
- App host and Postgres host as separate machines, load generator on a third (or documented fallback when only two machines exist). Remote execution over SSH or Docker contexts, documented.
- **Done when:** D3 runs from one `run.sh` command given host addresses; validated locally with two Docker hosts/VMs where possible.

### [ ] T33 Bottleneck detection and efficiency metrics
- Branch: `feat/t33-bottleneck`
- Classify each run as `app-bound`, `db-bound`, `pool-bound` or `load-generator-bound` from sampled app CPU, DB CPU, pool-wait time and k6 host CPU. Thresholds documented and configurable.
- Add capacity per vCPU and capacity per dollar-hour to `summary.json`.
- **Done when:** classification and efficiency fields appear in every summary and are explained in the README; unit-tested with synthetic samples.

### [ ] T34 First comparison report
- Branch: `feat/t34-report`
- Script that turns `results/` into a Markdown table committed under `docs/results/`, one table per scenario, including bottleneck column, efficiency metrics, environment and caveats.

---

## Phase 4: Kubernetes scenarios (K0-K2, k3d locally)

Locally, multi-node is simulated with k3d; it validates the setup, not the numbers. Official K1/K2 numbers come from Phase 7.

### [ ] T40 Cluster tooling and base manifests
- Branch: `feat/t40-k8s-base`
- `./run.sh k8s-up|k8s-down` (k3d, node count configurable), Kustomize manifests for Postgres (StatefulSet + seed Job) and a selectable backend (Deployment, Service, probes, resource requests/limits from the profile). No dependency on k3s-specific defaults (no Traefik); use a plain Service or port-forward for load.
- Manifest validation (kubeconform) in CI.
- **Done when:** each backend runs on the cluster and passes conformance through the Service.

### [ ] T41 Scenario K0 and fixed replicas
- Branch: `feat/t41-k8s-k0`
- K0 (1 node, 1 replica, hardware identical to D1) and `bench --scenario K0`. Fixed-replica support (`--replicas N`) recorded in results.
- **Done when:** K0 results are directly comparable with D1 (same profile and search procedure).

### [ ] T42 Scenario K1: scale the backend, fixed Postgres
- Branch: `feat/t42-k8s-k1`
- Multi-node layout: Postgres pinned to a dedicated node (node selector/taint), app replicas on other nodes, load generator on its own node.
- **Connection-limit decision (ask the human first):** raise Postgres `max_connections` vs add PgBouncer. Record the choice and its effect in docs.
- Manual replica sweep (1/2/4/8) and results showing where the single Postgres caps scaling.
- **Done when:** K1 sweep runs unattended on a k3d multi-node cluster and the summary includes the bottleneck classification per replica count.

### [ ] T43 HPA and spike tests
- Branch: `feat/t43-k8s-hpa`
- metrics-server + CPU-based HPA on K1; spike scenario (baseline then instant multiple). Metrics: time-to-first-new-pod-ready, time-to-stabilize, p99 and error rate during the spike.

### [ ] T44 Cold-start measurement
- Branch: `feat/t44-cold-start`
- Time from pod creation to first `/health` OK and first `/feed` OK, repeated N times, median + spread.

### [ ] T45 Spec v2: read/write split
- Branch: `feat/t45-spec-v2`
- **Requires human approval of the design before any code.** Adds a second connection setting (e.g. `READ_DATABASE_URL`) so reads can target replicas while writes target the primary. Keeps one query per request. Spec/ENV/conformance updated; all existing backends migrated in the same task or a follow-up per backend (human decides).
- **Done when:** all implemented backends pass conformance in both single-DB mode and read/write-split mode.

### [ ] T46 Scenario K2: scale backend and database
- Branch: `feat/t46-k8s-k2`
- Postgres primary + read replicas via CloudNativePG (or alternative the human approves), `-rw` and `-ro` Services wired to backends, replica sweep for the DB alongside the backend sweep.
- **Done when:** K2 runs on the k3d multi-node cluster and results show whether adding replicas moves the ceiling compared with K1.

---

## Phase 5: Observability

### [ ] T50 Prometheus + Grafana
- Branch: `feat/t50-observability`
- Compose and k8s deployments, k6 Prometheus remote-write output, cAdvisor/kube-state or equivalent for CPU/RAM, retention kept small.
- Provisioned dashboards (as code): latency percentiles, RPS, errors, CPU, RAM, replica count.
- **Done when:** a run is visible live in Grafana without manual setup.

---

## Phase 6: Frontend

> Detailed planning for this phase happens together with the human before it starts (stack, runner API, how runs are triggered and stored).

### [ ] T60 Runner API
- Branch: `feat/t60-runner-api`
- Small service that starts/stops runs, streams status, serves stored results.

### [ ] T61 Frontend MVP
- Branch: `feat/t61-frontend`
- Pick backend + mode + profile, start a run, live progress and key metrics, results table.

### [ ] T62 Comparison views
- Branch: `feat/t62-frontend-compare`
- Compare backends and modes, charts for latency and capacity, run history, export.

---

## Phase 7: AWS runbook

### [ ] T70 AWS runbook and automation
- Branch: `feat/t70-aws`
- Step-by-step guide (account, billing alerts, key pair, security groups), scripted create/destroy of EC2 instances (compute-optimized, not burstable), multi-node k3s for K1/K2, separate DB and app hosts for D3, separate load-generator node, price-per-hour inputs for the efficiency metrics, cost guardrails and teardown checklist.
- **Done when:** one official run of each scenario (D1-D3, K0-K2) executed and documented, with all resources confirmed destroyed afterwards.

---

## Phase 8: More languages

One task per language, same template as Phase 1 (branch `feat/t8x-backend-<lang>`), the frontend and docs updated each time. Suggested order, easiest first:

1. Rust (Axum + SQLx)
2. Java (Spring Boot)
3. C# (ASP.NET Core)
4. Bun (Express-compatible code)
5. Kotlin (Ktor)
6. PHP (Laravel + PHP-FPM; later bare PHP / Octane variants)
7. Ruby (Rails or Hanami)
8. Elixir (Phoenix)
9. Swift (Vapor)
10. C++ (Crow or Pistache)

---

## Decisions log

| # | Decision | Status |
|---|---|---|
| 1 | PostgreSQL only (SQLite does not fit multi-pod) | decided |
| 2 | Local-first (k3d), AWS (EC2 + k3s) for official runs | decided |
| 3 | First backends: Python, Go, Node.js | decided |
| 4 | Auth via HMAC-signed tokens verified in-process | decided |
| 5 | Default `base` profile: app 1 vCPU / 512 MiB, Postgres 1 vCPU / 1 GiB; expected to be raised after testing | decided (placeholder, tune in Phase 3) |
| 6 | Repository license: Apache-2.0 | decided |
| 7 | Scenario matrix D1, D2, D3, K0, K1, K2 plus bottleneck detection and efficiency metrics | decided |
| 8 | Frontend/runner stack | open (decide before T60) |
| 9 | Connection limits at scale: raise `max_connections` vs PgBouncer | open (decide in T42) |
| 10 | Read replicas via spec v2 and CloudNativePG | open (design approval before T45) |
