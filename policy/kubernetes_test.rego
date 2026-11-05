# Unit tests for the policies: proves they catch insecure manifests.
# Run with: conftest verify --policy policy/
package main

import rego.v1

secure_deployment := {
	"kind": "Deployment",
	"metadata": {"name": "ok", "namespace": "platform"},
	"spec": {"template": {"spec": {
		"automountServiceAccountToken": false,
		"securityContext": {"runAsNonRoot": true, "seccompProfile": {"type": "RuntimeDefault"}},
		"containers": [{
			"name": "app",
			"image": "ghcr.io/x/app:3f2a9c1",
			"securityContext": {
				"readOnlyRootFilesystem": true,
				"allowPrivilegeEscalation": false,
				"privileged": false,
				"capabilities": {"drop": ["ALL"]},
			},
			"resources": {"limits": {"memory": "128Mi"}},
		}],
	}}},
}

test_secure_deployment_passes if {
	count(deny) == 0 with input as secure_deployment
}

test_root_pod_denied if {
	bad := json.patch(secure_deployment, [{"op": "replace", "path": "/spec/template/spec/securityContext/runAsNonRoot", "value": false}])
	count(deny) > 0 with input as bad
}

test_privileged_container_denied if {
	bad := json.patch(secure_deployment, [{"op": "replace", "path": "/spec/template/spec/containers/0/securityContext/privileged", "value": true}])
	count(deny) > 0 with input as bad
}

test_latest_tag_denied if {
	bad := json.patch(secure_deployment, [{"op": "replace", "path": "/spec/template/spec/containers/0/image", "value": "nginx:latest"}])
	count(deny) > 0 with input as bad
}

test_missing_memory_limit_denied if {
	bad := json.patch(secure_deployment, [{"op": "remove", "path": "/spec/template/spec/containers/0/resources"}])
	count(deny) > 0 with input as bad
}

test_token_automount_denied if {
	bad := json.patch(secure_deployment, [{"op": "replace", "path": "/spec/template/spec/automountServiceAccountToken", "value": true}])
	count(deny) > 0 with input as bad
}

test_missing_seccomp_denied if {
	bad := json.patch(secure_deployment, [{"op": "remove", "path": "/spec/template/spec/securityContext/seccompProfile"}])
	count(deny) > 0 with input as bad
}

# Regression test: a missing field must be denied, not silently allowed.
test_missing_privilege_escalation_field_denied if {
	bad := json.patch(secure_deployment, [{"op": "remove", "path": "/spec/template/spec/containers/0/securityContext/allowPrivilegeEscalation"}])
	count(deny) > 0 with input as bad
}

test_missing_token_automount_field_denied if {
	bad := json.patch(secure_deployment, [{"op": "remove", "path": "/spec/template/spec/automountServiceAccountToken"}])
	count(deny) > 0 with input as bad
}
