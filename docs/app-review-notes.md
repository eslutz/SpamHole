# App Review preparation

SpamHole is call-only. It uses public CallKit Call Directory APIs to install local
telephone-number identification and blocking lists. Incoming calls do not trigger
server queries. There is no live caller lookup extension, Message Filter
extension, message access, public crowdsourcing service, or nonstandard
background mode.

FTC evidence consists of unverified complaints. It only produces neutral caller
identification, such as "Reported unwanted"; it cannot authorize automatic
blocking. Explicit personal block rules are user-directed. Custom lists remain
untrusted identification evidence and cannot assign confirmation authority.
Automatic call blocking would require reviewed, current source confirmation;
no such authority is enabled in this build.

The containing app periodically refreshes complete datasets when iOS grants
execution opportunities. Requested cadence is not a guaranteed timer. The app
shows data refresh, snapshot generation and Call Directory installation state
separately. Installed call entries have no per-entry expiration API.

Public submission remains pending physical-call acceptance, Contacts behavior,
VoiceOver, signing and distribution review. Complete this document with the
release candidate's source contract, recorded acceptance results, reviewer
instructions and a reviewable TestFlight build before use. Historical SMS
research is outside the current product scope and is not a release requirement.
