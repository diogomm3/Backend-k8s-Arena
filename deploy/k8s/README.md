# Kubernetes Manifests

Kustomize manifests for Kubernetes scenarios (T40-T46).

- Postgres (StatefulSet + seed Job)
- Backend (Deployment, Service, probes, resource requests/limits from profile)
- No dependency on k3s-specific defaults (no Traefik)
- Manifest validation (kubeconform) in CI