# Privacy policy — SpamHole development version

Reviewed October 4, 2026. Public static policy and support pages are maintained
in [`site/privacy.html`](site/privacy.html) and [`site/support.html`](site/support.html). This policy describes
the development source and must be rechecked against the distributed binary.

SpamHole stores personal call allow/block rules, source subscriptions, downloaded
public evidence, preferences, and generated protection snapshots locally.
Optional Contacts access is used only to protect accessible contact numbers from
this app's automatic decisions. Names are not requested or cached; local
protection snapshots may contain allow entries derived from contact numbers.
Contacts are not uploaded, and explicit personal rules take priority.
The shared data directory is excluded from automatic device backups. Its files
use iOS protection that permits Call Directory extension access after the first
device unlock.

The containing app requests complete, non-personalized datasets from subscribed
publishers. Those publishers receive ordinary request metadata, including IP
address, requested URL, timing, and request headers. Public background downloads
include a SpamHole application identifier. API credentials, if
configured, are stored in the iOS Keychain and sent only to their intended source.
Custom-source credentials use device-only Keychain storage and are not included
in rule backups. Credentialed transfers restrict redirects to the same HTTPS
host and port. Publisher metadata retention is controlled by each publisher.
Disabling a source stops future refreshes but does not delete its credential;
a transfer already handed to iOS may finish.

Incoming caller numbers are matched by iOS against the installed Call Directory.
SpamHole is call-only and has no access to messages. It does not contain a
Message Filter extension or request message access.
There is no call-history collection, usage analytics, advertising, crash-upload
SDK, public report submission, or account service.

User-requested rule backup contains personal telephone numbers, rule details
(including saved correction notes), and settings. It excludes contacts, source
subscriptions, credentials, and downloaded evidence. The user chooses where to
save or share it, including any cloud destination. A successful import replaces
personal rules and settings and leaves Contacts protection off. New exports use
schema version 2 and contain call rules only. Legacy version 1 backups retain
valid telephone-number call rules and convert the call portion of former combined
rules; message-only rules are omitted, and converted/omitted counts are shown.
Short codes are never promoted to call numbers. A nonempty message-only backup
is rejected without changing existing rules; an explicitly empty rules list can
clear them. Invalid backups are rejected before atomic replacement.

Upgrading from the former call/SMS development build does not automatically
erase all old local data. Legacy SMS-only records may remain dormant in local
storage for compatibility; they are excluded from active call protection and
new rule exports. The current app has no message access.

Individual rules can be removed in Lookup. Removing a custom source deletes its
saved Keychain token and subscription; disabling/removing a source eliminates
active contributions on the next snapshot rebuild. Installed call entries change
only after successful Call Directory reload. Old protection generations and
temporary downloads may remain until cleanup runs. Deleting, rather than
offloading, the app removes app-managed storage according to iOS behavior.
Remove custom sources before uninstalling to clear their saved Keychain tokens;
do not assume uninstall deletes Keychain items. Exported/shared files must be
removed separately. The app cannot delete publisher request logs or support posts.

The static policy/support pages have no page-code cookies, JavaScript, analytics,
forms, or external assets. The web host still receives page-load requests.
Public support uses repository issues and must contain only synthetic/redacted
data. Security vulnerabilities use GitHub private reporting.

The public [privacy policy](https://spamhole.ericslutz.dev/privacy.html) and
[support page](https://spamhole.ericslutz.dev/support.html) are deployed from
`docs/site/` using GitHub Pages with `spamhole.ericslutz.dev` configured as the
custom domain. HTTPS requires GitHub to issue the domain certificate.
This policy must still be checked against the final distributed binary and
reviewed before App Store submission.
