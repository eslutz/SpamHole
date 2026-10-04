# Security policy

This project is under development. No released version is currently certified
production-ready; fixes target the current main branch.

Report vulnerabilities using GitHub's private vulnerability reporting for this
repository. Do not publish tokens, signing material, contacts or message records
in an issue. Use synthetic reproduction data.

Incoming calls must not generate server lookups. Contacts and private call rules
remain local. SpamHole has no access to messages. Custom sources are untrusted;
a subscription cannot grant confirmation authority. Failed snapshot publication
or call reload must preserve and accurately report the last installed state.

Before publishing changes, review the staged file list and run Gitleaks against
a clean export of the Git index. Ignore rules are defense in depth, not a secret
scanner. If a credential is exposed, revoke/rotate it; deleting a file alone does
not remove the exposure from history.
