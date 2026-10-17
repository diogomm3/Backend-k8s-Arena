# Conformance Suite

Black-box test suite runnable against any base URL (T04).

- ~40 checks: status codes, auth rules, validation, error bodies, idempotent like
- Reference snapshot from seed (regeneration documented)
- Runs through Docker: `./run.sh conformance --backend <name>`
