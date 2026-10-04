# Security policy

This project is under development. No released version is currently certified
production-ready; fixes target the current main branch.

Report vulnerabilities using GitHub's private vulnerability reporting for this
repository. Do not publish tokens, signing material, contacts or message records
in an issue. Use synthetic reproduction data.

Incoming calls/messages must not generate server lookups. Contacts, private rules
and message senders remain local. Custom sources are untrusted; a subscription
cannot grant confirmation authority. Missing/invalid SMS snapshots fail open.

Before publishing changes, review the staged file list and run Gitleaks against
a clean export of the Git index. Ignore rules are defense in depth, not a secret
scanner. If a credential is exposed, revoke/rotate it; deleting a file alone does
not remove the exposure from history.
