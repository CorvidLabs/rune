---
hi: 1
families: [SESSION]
---

# A session that outlives the call

## Intent

An agent CLI is a conversation, and a conversation cannot live inside a single command invocation. A session holds one of those programs open under a name, so you can start it now, talk to it from another process later, and still be talking to the same program with the same state. Sessions should be easy to have several of and hard to lose track of: named, listed with enough information to tell working from stuck, scoped to the project you are standing in, and cleanly disposable when you are done. Nothing rune says about a session should be a stale note on disk when the truth is a process you could have looked at.

## Criteria

- **SESSION-1**  A session I start keeps its program running after the command that started it has exited.
- **SESSION-2**  I can come back to the same session later — from another process, another agent, another hour — and find the same program with the same state.
- **SESSION-3**  Every session has a name I can address it by.
  - **SESSION-3.a**  I only have to choose a name when I care which one it is.
  - **SESSION-3.b**  A session started without a name gets a memorable codename that nothing else is using.
- **SESSION-4**  Sessions belong to the directory I am working in, so the same name in two checkouts is two different sessions.
  - **SESSION-4.a**  Starting a session tells me which project it landed in, because that is the first thing I need when I cannot find it again.
  - **SESSION-4.b**  I can list every session everywhere when the one I want is not in this project.
  - **SESSION-4.c**  When the session I asked for is not in this project but exists in another, the answer tells me where it is instead of just saying no.
- **SESSION-5**  A command that cannot be launched at all is a failure rather than a session.
- **SESSION-6**  A program that starts and then exits immediately comes back as a launch that worked, not as a session that failed to start.
- **SESSION-7**  I can see at a glance which of my sessions are running.
  - **SESSION-7.a**  The listing tells me how long each session has been quiet.
  - **SESSION-7.b**  The listing tells me what each session last printed, so I can tell working from stuck.
- **SESSION-8**  What rune says about a session being alive comes from looking at the real processes, not from what was written down last.
- **SESSION-9**  Stopping a session leaves nothing of it still running.
  - **SESSION-9.a**  Stopping has finished by the time it returns, rather than merely having been asked for.
- **SESSION-10**  A session that has ended records how it ended, so the program finishing, my stopping it, and a launch that never happened are three different answers.
- **SESSION-11**  I can archive a stopped session so its name is free to use again.
  - **SESSION-11.a**  Archiving keeps the transcript, so I can still read what happened.
  - **SESSION-11.b**  Reusing a name starts genuinely fresh rather than continuing an older session's transcript.
- **SESSION-12**  A program that does not speak Ruby can drive a session directly, without going through the command line.
- **SESSION-13**  One session going wrong takes down only itself and leaves my other sessions running.
- **SESSION-14**  What a session recorded is readable only by me.
- **SESSION-15**  I can keep a set of sessions apart from my usual ones, so a sandbox or a test run never touches them.
