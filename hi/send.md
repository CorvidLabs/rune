---
hi: 1
families: [SEND]
---

# Driving the program on the other end

## Intent

This is what a persistent session is for: ask the program something and get its answer back, the way a function call does. rune should turn an asynchronous terminal into a request and a reply — write the text, wait until the other end has really answered, hand back exactly what this turn produced. Knowing when a program has finished talking is genuinely hard, so rune should give more than one way to decide, say in every reply which way decided it, and be candid about the cases where it cannot tell. Nothing I did not mean to type should ever reach the program, and nothing that failed to reach it should look like it arrived.

## Criteria

- **SEND-1**  I can send text to a session's program and get back exactly the output that send produced.
- **SEND-2**  The call waits until the program has actually answered, so a turn reads as a request and a reply.
- **SEND-3**  I can say how long a quiet stretch has to be before rune calls the turn finished.
- **SEND-4**  My own words coming back as the terminal's echo do not count as the program having answered.
- **SEND-5**  I can wait for output matching a pattern instead, for when I know what the program prints when it is done.
  - **SEND-5.a**  A pattern is matched against the program's answer rather than against the echo of what I sent.
  - **SEND-5.b**  A pattern that will not compile is refused before anything is typed at the program.
  - **SEND-5.c**  Rune says plainly that a pattern can match a repaint of something older than the question I just asked.
- **SEND-6**  Every wait has a hard ceiling I can set.
  - **SEND-6.a**  Reaching that ceiling hands back what was captured rather than failing.
- **SEND-7**  The reply says which of the possible reasons ended the wait, so I never have to infer it.
- **SEND-8**  I can write something and return immediately when I am not expecting a reply at all.
- **SEND-9**  I can write text without submitting it, for composing a line in pieces or driving a program that reads keystrokes.
- **SEND-10**  Pressing enter reaches the program the way a real terminal's enter does, so full-screen programs receive it.
- **SEND-11**  The reply tells me whether the program was still printing when my text landed, so an answer that belongs to the previous question is recognisable.
- **SEND-12**  A send to a program that has already exited comes back as an error naming the state, not as silence.
- **SEND-13**  A second send arriving while one is still in flight is refused rather than interleaved with it.
- **SEND-14**  Text that never reached the program comes back as a failure rather than as a send that looks like it happened.
- **SEND-15**  A mistyped flag is refused rather than typed at the program as though it were part of my message.
- **SEND-16**  Rune says plainly where a quiet program cannot be told from a finished turn, instead of guessing on my behalf.
