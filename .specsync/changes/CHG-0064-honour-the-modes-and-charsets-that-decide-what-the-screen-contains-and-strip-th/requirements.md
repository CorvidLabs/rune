---
change: CHG-0064-honour-the-modes-and-charsets-that-decide-what-the-screen-contains-and-strip-th
artifact: requirements
---

# Requirements

1. The alternate screen buffer hides the primary buffer and discards its own
   contents on exit; 1049 saves and restores the cursor, 1047 and 47 do not.
2. DECAWM off suppresses the wrap; on restores it; absent means on.
3. IRM shifts the line right rather than overwriting.
4. `ESC ( 0` and SO/SI produce line-drawing glyphs, and no other designation
   guesses at a national set.
5. `clean_output` contains no escape bytes.
6. None of the above changes what a plain, escape-free stream renders.
