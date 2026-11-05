#!/usr/bin/env bash
# Deploys the hardened 3-tier app into the current kubectl context.
set -euo pipefail
cd "$(dirname "$0")/.."

kubectl apply -f k8s/00-namespace.yaml

# Redis config with a random password, generated here and never committed.
if ! kubectl -n platform get secret redis-config >/dev/null 2>&1; then
  password="$(openssl rand -hex 24)"
  kubectl -n platform create secret generic redis-config \
    --from-literal=redis.conf="$(printf 'requirepass %s\nsave ""\nappendonly no\n' "$password")"
fi

kubectl apply -f k8s/

for d in redis api frontend; do
  kubectl -n platform rollout status "deployment/$d" --timeout=180s
done
echo "Deployment complete."
