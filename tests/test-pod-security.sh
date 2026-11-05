#!/usr/bin/env bash
# Proves the API server itself rejects insecure pods in the platform namespace.
# Uses server-side dry-run: the request goes through admission control,
# but nothing is created.
set -uo pipefail
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"
echo "== Pod Security admission =="

try_pod() {
  kubectl apply --dry-run=server -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: probe
  namespace: platform
spec:
  containers:
    - name: c
      image: busybox:1.37
$1
EOF
}

expect_fail "privileged container is rejected" try_pod "      securityContext: { privileged: true }"
expect_fail "container running as root is rejected" try_pod "      securityContext: { runAsUser: 0 }"
expect_fail "hostPath volume is rejected" kubectl apply --dry-run=server -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata: { name: probe, namespace: platform }
spec:
  containers: [{ name: c, image: busybox:1.37 }]
  volumes: [{ name: host, hostPath: { path: / } }]
EOF
expect_ok "fully hardened pod is accepted" try_pod "      securityContext:
        runAsNonRoot: true
        runAsUser: 10009
        allowPrivilegeEscalation: false
        capabilities: { drop: [ALL] }
        seccompProfile: { type: RuntimeDefault }"

summary "Pod Security"
