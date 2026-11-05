#!/usr/bin/env bash
# One-command local environment: kind + Calico + app + Falco + all tests.
# Requires: docker, kind, kubectl, helm. Expects the secure-cicd-pipeline repo
# cloned next to this one (it provides the API image).
set -euo pipefail
cd "$(dirname "$0")/.."
CALICO_VERSION=v3.32.3
FALCO_CHART_VERSION=9.2.2

kind create cluster --config kind/cluster.yaml
kubectl apply -f "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/calico.yaml"
kubectl -n kube-system rollout status daemonset/calico-node --timeout=300s
kubectl wait --for=condition=Ready nodes --all --timeout=300s

docker build -t task-api:e2e ../secure-cicd-pipeline
kind load docker-image task-api:e2e --name hardened

./scripts/deploy.sh

helm repo add falcosecurity https://falcosecurity.github.io/charts >/dev/null
helm upgrade --install falco falcosecurity/falco --version "$FALCO_CHART_VERSION" \
  --namespace falco --create-namespace -f falco/values.yaml --wait --timeout 5m

status=0
for t in tests/test-*.sh; do bash "$t" || status=1; echo; done
exit $status
