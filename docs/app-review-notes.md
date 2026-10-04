# App Review preparation

SpamHole uses public CallKit Call Directory APIs to install local number lists
and IdentityLookup to classify SMS/MMS from unknown senders. Calls and messages
do not trigger server queries. There is no live caller lookup extension, message
deferral endpoint, public crowdsourcing service, or nonstandard background mode.

FTC evidence consists of unverified complaints. It only produces neutral caller
identification, such as "Reported unwanted"; it cannot authorize automatic
blocking. Explicit personal block/Junk rules are user-directed. Custom lists
remain untrusted identification evidence and cannot assign confirmation grades.
All automatic decisions require reviewed, current source confirmation specific
to the communication channel. No such authority is enabled in this build.

The containing app periodically refreshes complete datasets when iOS grants
execution opportunities. Requested cadence is not a guaranteed timer. The app
shows data refresh, snapshot generation and Call Directory installation state
separately. Installed call entries have no per-entry expiration API.

IdentityLookup filtering is limited to SMS/MMS from unknown senders; iMessage is
not supported. The extension reads an immutable shared snapshot, fails open on
errors or expired feed decisions, and records no message content or event log.

Public submission remains blocked on the required vetted SMS feed and physical
device acceptance. Complete this document with the enabled source contract,
evaluation results, instructions and a reviewable TestFlight build before use.
