# A Rego policy equivalent to the Keycloak demo realm.
#
# On the Keycloak side:
#   alice has the reader role, bob has no role
#   resource 123 (type: document) has the scope can_read
#   permission: can_read on 123 is granted by reader-policy (the reader role)
#
# The contrib authzen-proxy passes the AuthZEN evaluation request straight
# through as OPA's input and returns the `result` of /v1/data/<OPA_POLICY_PATH>
# as the response body. So this package builds {"decision": true|false}.

package authzen

import rego.v1

# Roles assigned to each subject (equivalent to Keycloak role mappings)
user_roles := {
	"alice": {"reader"},
	"bob": set(),
}

# Resources and the scopes evaluated on them (equivalent to Keycloak resources)
resources := {"123": {
	"type": "document",
	"scopes": {"can_read"},
}}

# Roles granted per scope (equivalent to Keycloak permissions)
scope_roles := {"can_read": {"reader"}}

default allow := {"decision": false}

allow := {"decision": true} if {
	res := resources[input.resource.id]
	res.type == input.resource.type
	input.action.name in res.scopes
	roles := user_roles[input.subject.id]
	count(roles & scope_roles[input.action.name]) > 0
}
