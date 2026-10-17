# AGENT.md

Instructions for the AI coding agent working on **Backend-k8s-Arena**. Read this file, `README.md` and `docs/IMPLEMENTATION_PLAN.md` before doing anything, and re-read them at the start of every task.

## 1. Mission

Build a fair, reproducible benchmark that compares the same social-feed API across backend stacks in Docker and Kubernetes. The methodology in `README.md` and the contract in `spec/` are the source of truth. **Fairness and correctness matter more than speed or cleverness.**

## 2. Working agreement (human in the loop)

1. **One task at a time**, taken from `docs/IMPLEMENTATION_PLAN.md`. Never start a task the human has not named.
2. **Plan first, code after approval.** For each task, reply with a short plan (files to create/change, key decisions, risks, open questions) and **wait for explicit approval** before writing code.
3. If something is ambiguous or contradicts the spec, **ask**. Do not guess, and do not silently change the spec, the methodology or the plan.
4. **No scope creep.** No extra features, frameworks, optimizations or refactors outside the task. Note ideas in the feedback report instead.
5. After finishing, post the **feedback report** (section 7) and wait for review.

## 3. Git workflow

- Never commit to `main`. Never force-push shared branches. Never merge your own PR; the human merges.
- One branch per task: `feat/<task-id>-<slug>` (`fix/...`, `docs/...`, `chore/...` for other work).
- Small, focused commits using Conventional Commits (`feat(backend-go): add feed endpoint`). Whenever possible try to commit the files one by one.
- Open a PR per task against `main` using the PR template: summary, what changed, how to test, checklist, link to the plan task.
- A PR is ready for review only when **CI is green** and the checklist is complete.
- Update the roadmap/task checkboxes and docs in the same PR as the change.
- Never delete branches, local or remote, before or after a merge (no `git branch -d/-D`, no `git push --delete`, no `gh pr merge --delete-branch`, no pruning of branches you did not create). Merged branches are left untouched. After the human merges, only sync: `git fetch --prune`, `git checkout main`, `git pull`. (`--prune` only drops stale remote-tracking references, never branches.)
- Use the GitHub CLI (`gh`) to open PRs: write the body to a file and use `gh pr create --body-file`. The human reviews and merges on GitHub.

## 4. CI and quality gates

GitHub Actions must run on every PR (path-filtered where sensible):

- lint/format for every language touched, plus markdown, YAML and `shellcheck`;
- build of each changed Docker image (`linux/amd64` and `linux/arm64`, build only, no push);
- the **conformance suite** against each changed backend with a small seed;
- check that each backend's SQL matches `spec/queries.sql` verbatim;
- Kubernetes manifest validation (kubeconform) once manifests exist.

Full benchmarks are **never** run in CI (shared runners are too noisy). Only short smoke runs are allowed. Do not disable, skip or weaken a check to make CI pass; fix the cause or ask.

## 5. Coding rules

### General

- Pin all versions (base images, language runtimes, dependencies, GitHub Actions). No `latest` tags.
- No secrets in the repo. Configuration through environment variables documented in `spec/ENV.md`.
- Prefer boring, standard-library-first, readable code. Comment the *why*, not the *what*.
- Scripts: Bash with `set -euo pipefail`, idempotent where possible, clear error messages, passing `shellcheck`.
- Every new command or option is documented in `README.md`.

### Backends (fairness rules; do not break these)

- Implement exactly `spec/API.md`. Use the canonical SQL from `spec/queries.sql` verbatim.
- **No ORM, no caching, one DB query per request**, pool size `DB_POOL_SIZE` (default 10) **per process**.
- Auth tokens verified in-process (HMAC), no DB lookup.
- One framework per language, using its normal production defaults. Do not hand-tune a backend beyond what the others get. Document any non-default setting in that backend's `README.md`.
- Production build/mode only, access logging off in the hot path, graceful shutdown, `GET /health` without DB access.
- Same behaviour as every other backend; the conformance suite is the judge.

### Docker

- Multi-stage builds, small final image, non-root user, `.dockerignore`, `HEALTHCHECK`, deterministic builds, multi-arch.
- Resource limits come from the profile files, never hard-coded in images.

### Kubernetes

- Standard Kubernetes only: no dependency on k3s/k3d-specific defaults (e.g. Traefik). Resource requests/limits, readiness/liveness probes, labels on everything. Kustomize for variants.

### Benchmarking

- Never run load tests against anything but local/own infrastructure.
- Results are written in the documented `summary.json` schema with full environment info (CPU, cores, RAM, OS, tool versions, profile). Never hand-edit results.
- Never present local-laptop results as official.

## 6. Testing expectations

- Every backend passes the full conformance suite before the PR is opened.
- New scripts/tools get at least a basic automated check or a documented manual test.
- State exactly what you ran and what you did **not** run. Do not claim something works unless you executed it.

## 7. Feedback report (after every task)

Post this in the PR description and in the chat when the task is finished:

```markdown
## Task <id>: <title>
**Status:** done / blocked / partially done
**What I did:** (bullets)
**How to verify:** (exact commands)
**What I ran and the results:** (tests, CI, manual checks)
**Not done / not verified:** (be explicit)
**Deviations from the plan or spec:** (and why; none if none)
**Open questions / risks:**
**Suggested next step:**
```

## 8. Safety rails

- Do not install global tooling or modify the host outside the repo and Docker/k3d without asking.
- Do not delete data or resources you did not create. Cloud (AWS) actions require explicit approval each time and must include a teardown step and a cost estimate.
- Never commit large generated data (seeds are generated, results are git-ignored except curated samples).
- When blocked, stop and ask rather than working around the problem.
