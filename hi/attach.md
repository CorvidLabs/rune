---
hi: 1
families: [ATTACH]
---

# Taking the wheel

## Intent

Anything an agent is driving, a person should be able to step into and drive by hand — and then step back out of without ending it. Attaching should feel like the program was always yours: the current screen is already there, it lays itself out for your window, and your keystrokes go straight through. Leaving is one keystroke and changes nothing about the session. Nothing you do at an attached terminal, including a connection dying badly, may take the session down.

## Criteria

- **ATTACH-1**  I can attach my own terminal to a running session and drive it myself.
- **ATTACH-2**  Attaching replays the current screen, so I am not left staring at a blank one.
- **ATTACH-3**  The program is resized to my terminal while I am attached.
  - **ATTACH-3.a**  The program returns to its usual size when I leave.
- **ATTACH-4**  One keystroke detaches me and leaves everything running.
  - **ATTACH-4.a**  Ctrl-C is not that keystroke, because it has to keep reaching the program so I can interrupt a runaway.
- **ATTACH-5**  More than one viewer can be attached at once.
  - **ATTACH-5.a**  One viewer going away does not disturb the others.
- **ATTACH-6**  Nothing I do at an attached terminal, including disconnecting badly, can take the session down.
