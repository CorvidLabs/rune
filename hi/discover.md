---
hi: 1
families: [DISCOVER]
---

# Finding out what rune can do

## Intent

An agent arriving at rune for the first time should be able to learn the whole surface from rune itself, in one round trip, without scraping text written for people. Help is a normal result, so it is available as data; the wire contract — every field, every failure code, every state — is published the same way. The published description has to be the one rune is actually held to, and it should name the traps as well as the fields, because the dangerous replies here are the ones that say everything worked.

## Criteria

- **DISCOVER-1**  I can ask rune what commands it has and what each one is for.
- **DISCOVER-2**  I can ask one command for its usage and its own flags.
- **DISCOVER-3**  A command with subcommands lists them the way the top level lists commands, so one reader handles both levels.
- **DISCOVER-4**  Help is available as data, so a program discovers the surface without scraping the version written for people.
- **DISCOVER-5**  Asking for help never runs the command I asked about.
- **DISCOVER-6**  I can get the whole wire contract — every reply field, every failure code, every state — as machine-readable data.
  - **DISCOVER-6.a**  The published contract is the same one rune's own tests hold it to, so it cannot describe a rune that does not exist.
- **DISCOVER-7**  The contract names the field states that mean the call worked but the thing I wanted did not happen.
- **DISCOVER-8**  The contract names the known ways each verb can mislead me.
- **DISCOVER-9**  I can ask rune which version it is, so I know what I am talking to before I rely on it.
- **DISCOVER-10**  I can read rune's guides in my own language.
  - **DISCOVER-10.a**  The English guide is authoritative wherever a translation disagrees with it.
