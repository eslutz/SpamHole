# Privacy policy — SpamHole development version

SpamHole stores personal allow/block rules, source subscriptions, downloaded
public evidence, preferences, and generated protection snapshots locally.
Optional Contacts access is used only to protect accessible contact numbers from
this app's automatic decisions. Contacts are not uploaded.
The shared data directory is excluded from automatic device backups. Its files
use iOS protection that permits extension access after the first device unlock;
missing or inaccessible SMS snapshots produce no Junk decision.

The containing app requests complete, non-personalized datasets from subscribed
publishers. Those publishers receive ordinary request metadata, including IP
address, timing, and a SpamHole application identifier. API credentials, if
configured, are stored in the iOS Keychain and sent only to their intended source.
Custom-source credentials are not included in backups.

Incoming caller numbers are matched by iOS against the installed Call Directory.
The SMS extension matches a sender locally. It does not transmit, record, or
inspect message bodies, and does not write message activity to shared storage.
There is no call-history collection, usage analytics, advertising, crash-upload
SDK, public report submission, or account service.

User-requested rule backup contains personal sender identifiers and settings.
The user chooses where to save or share it. Deleting the app removes its local
storage according to iOS behavior; credentials can be removed in source settings.

This policy must be checked against the final distributed binary and published
at a user-approved public URL before App Store submission.
