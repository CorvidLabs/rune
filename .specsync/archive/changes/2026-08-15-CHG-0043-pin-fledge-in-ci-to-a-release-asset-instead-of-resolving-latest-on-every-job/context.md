---
change: CHG-0043-pin-fledge-in-ci-to-a-release-asset-instead-of-resolving-latest-on-every-job
artifact: context
---

# Context

The fledge installer resolves its version through the unauthenticated GitHub API, which is rate
limited per IP. Actions runners share IPs, and this repo called it from seven jobs on every push.
When the shared quota was gone the lookup returned nothing and the job died with "could not
determine latest version".

Four CI runs were lost to it — Ruby 3.3, Ruby 3.2, and Spec Sync twice — and each looked like a real
failure until someone read the log.

The obvious fix was a marketplace action, and that was checked first: `CorvidLabs/fledge` has no
`action.yml` on any of its seven branches, unlike `CorvidLabs/spec-sync`, which ships one at its
root. Adding it there is the real fix and has been handed off; this is the part that belongs here.
