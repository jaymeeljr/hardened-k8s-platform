#!/usr/bin/env bash
# Network segmentation test. Starts probe pods that carry each tier's labels,
# then checks every path in the matrix: allowed paths must connect, everything
# else must be blocked.
set -uo pipefail
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"
echo "== NetworkPolicy segmentation =="

probe() {  # probe <name> <namespace> <component-label or "none">
  local labels=""
  [ "$3" != "none" ] && labels="app.kubernetes.io/component: $3"
  kubectl apply -f - >/dev/null <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: $1
  namespace: $2
  labels:
    role: probe
    $labels
spec:
  automountServiceAccountToken: false
  securityContext:
    runAsNonRoot: true
    runAsUser: 10009
    seccompProfile: { type: RuntimeDefault }
  containers:
    - name: probe
      image: busybox:1.37
      command: ["sleep", "3600"]
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities: { drop: [ALL] }
      resources:
        limits: { cpu: 50m, memory: 32Mi }
EOF
}

kubectl create namespace client --dry-run=client -o yaml | kubectl apply -f - >/dev/null
probe probe-frontend platform frontend
probe probe-backend  platform backend
probe probe-outsider platform none
probe probe-client   client   none
kubectl wait --for=condition=Ready pod -l role=probe -n platform --timeout=120s >/dev/null
kubectl wait --for=condition=Ready pod -l role=probe -n client   --timeout=120s >/dev/null
sleep 5  # let Calico program the new pods

tcp() { kubectl exec -n "$1" "$2" -- nc -z -w 3 "$3" "$4"; }
SVC=platform.svc.cluster.local

echo "-- allowed paths"
expect_ok   "external client -> frontend:8080"     tcp client probe-client frontend.$SVC 8080
expect_ok   "frontend -> api:8080"                 tcp platform probe-frontend api.$SVC 8080
expect_ok   "api -> redis:6379"                    tcp platform probe-backend redis.$SVC 6379
expect_ok   "end-to-end: client -> nginx -> api /health" \
  sh -c "kubectl exec -n client probe-client -- wget -q -T 5 -O- http://frontend.$SVC:8080/health | grep -q ok"

echo "-- blocked paths"
expect_fail "external client -> api (skipping frontend)"  tcp client probe-client api.$SVC 8080
expect_fail "external client -> redis"                    tcp client probe-client redis.$SVC 6379
expect_fail "frontend -> redis (skipping api)"            tcp platform probe-frontend redis.$SVC 6379
expect_fail "unlabeled pod in namespace -> api"           tcp platform probe-outsider api.$SVC 8080
expect_fail "api -> internet (1.1.1.1:443)"               tcp platform probe-backend 1.1.1.1 443
expect_fail "frontend -> internet (1.1.1.1:443)"          tcp platform probe-frontend 1.1.1.1 443

echo "-- authentication"
expect_ok "redis rejects unauthenticated clients (NOAUTH)" \
  sh -c "kubectl exec -n platform probe-backend -- sh -c 'printf \"PING\r\n\" | nc -w 2 redis.$SVC 6379' | grep -q NOAUTH"

kubectl delete pod -l role=probe -n platform --wait=false >/dev/null
kubectl delete namespace client --wait=false >/dev/null
summary "NetworkPolicy"
