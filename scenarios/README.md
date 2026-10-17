# Scenario Definitions

YAML files defining topology, hardware, DB mode, and scaling (T31, T42, T46).

Scenarios:
- D1: Docker, 1 VM, app + Postgres share it
- D2: Docker, 1 VM, bigger hardware (both / Postgres-only variants)
- D3: Docker, 2 VMs (app + Postgres separate)
- K0: Kubernetes, 1 node, 1 replica
- K1: Kubernetes, multi-node, fixed Postgres, scale backend
- K2: Kubernetes, multi-node, scale backend and database (read replicas)
