#!/usr/bin/env bash
set -euo pipefail

# Backend-k8s-Arena - single entry point for all operations
# Version: 0.1.0 (scaffold)

print_help() {
    cat <<'EOF'
Backend-k8s-Arena - Polyglot backend benchmark runner

Usage:
  ./run.sh <command> [options]

Commands:
  help                 Show this help message

  # Database (planned - not implemented yet)
  db-up                Start PostgreSQL container
  db-seed              Run deterministic seed (50k users, 500k posts, ~2M likes)
  db-reset             Drop and recreate database with fresh seed

  # Docker (planned - not implemented yet)
  up --backend <name>  Start Postgres + seed + backend (Docker Compose)
  down                 Stop and remove all containers
  conformance --backend <name>  Run conformance suite against backend

  # Benchmarking (planned - not implemented yet)
  bench --backend <name> --mode docker|k8s [--profile base] [--scenario D1|D2|D3|K0|K1|K2] [--replicas N] [--spike Nx]

  # Kubernetes (planned - not implemented yet)
  k8s-up               Create local k3d cluster
  k8s-down             Destroy k3d cluster

  # Observability (planned - not implemented yet)
  observability-up     Start Prometheus + Grafana
  observability-down   Stop Prometheus + Grafana

Options:
  --backend <name>     Backend to target: python, go, node
  --mode <mode>        Execution mode: docker, k8s, k8s-hpa
  --profile <name>     Resource profile: base (default)
  --scenario <id>      Scenario to run: D1, D2, D3, K0, K1, K2
  --replicas <n>       Number of backend replicas (Kubernetes)
  --spike <multiplier> Spike multiplier for HPA tests (e.g. 3x)
  --all                Run against all implemented backends sequentially
  -h, --help           Show help for specific command

Examples:
  ./run.sh help
  ./run.sh up --backend go
  ./run.sh conformance --backend python
  ./run.sh bench --backend go --mode docker --profile base
  ./run.sh bench --all --mode docker
  ./run.sh bench --backend go --scenario D2
  ./run.sh k8s-up
  ./run.sh bench --backend go --mode k8s --replicas 2
  ./run.sh bench --backend go --mode k8s-hpa --spike 3x
  ./run.sh down

Environment variables (see spec/ENV.md when available):
  PORT                 HTTP port (default: 8080)
  DATABASE_URL         PostgreSQL connection string
  DB_POOL_SIZE         Connection pool size per process (default: 10)
  TOKEN_SECRET         HMAC secret for auth tokens

EOF
}

not_implemented() {
    echo "Error: '$1' is not implemented yet" >&2
    echo "Run './run.sh help' to see planned commands" >&2
    exit 1
}

main() {
    if [[ $# -eq 0 ]]; then
        print_help
        exit 0
    fi

    case "${1:-}" in
        help|-h|--help)
            print_help
            ;;
        db-up|db-seed|db-reset|up|down|conformance|bench|k8s-up|k8s-down|observability-up|observability-down)
            not_implemented "$1"
            ;;
        *)
            echo "Error: Unknown command '$1'" >&2
            echo "Run './run.sh help' for usage" >&2
            exit 1
            ;;
    esac
}

main "$@"