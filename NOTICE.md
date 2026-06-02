# Provenance & Licensing

## This is original work

Long Live Pets is an **independent, clean-room implementation**. All of its code
was written from scratch for this project. It **does not contain, copy, or
adapt code from Rematch or from any other addon**, and it is not a fork or a
derivative of any existing addon.

It is offered under the **MIT License** (see `LICENSE`).

### Why it works like other team managers

Copyright protects the *expression* of software — the actual source code — not
its *ideas, behaviors, or functionality*. Saving battle-pet teams and loading
them back into the journal slots is a function, achieved here entirely through
Blizzard's public `C_PetJournal` API with our own original code. Resembling the
*behavior* of other pet-team managers is both intentional and legally fine; what
matters is that none of their *code* is used here, and none is.

## A note on Rematch

This project was **inspired by Rematch** (by Gello) — the addon that set the bar
for pet-team management. Rematch has no open-source license, so **none of its
code is used here**: every line of Long Live Pets is original. We give Gello a
sincere hat tip for the design ideas, nothing more. If Gello ever has a concern,
please open an issue and it will be addressed immediately.

## Third-party software (bundled)

- **tdBattlePetScript** by *DengSir* (Dengzhun Lu) — **MIT License.**
  This battle-script engine is **bundled** in the `tdBattlePetScript/` folder.
  It is DengSir's work, redistributed here under the terms of the MIT License
  with the original copyright notice and `LICENSE.md` retained **unmodified**
  (the MIT License expressly permits this). Long Live Pets adds only its own
  original glue code (`Integration/tdBattlePetScript.lua`) that hands off to
  tdBattlePetScript's public interface when a scripted team is loaded.
  Bundled libraries inside tdBattlePetScript (Ace3, LibStub, tdGUI, etc.) retain
  their own respective licenses.

## Trademarks / acknowledgements

World of Warcraft and the `C_PetJournal` API are the property of Blizzard
Entertainment. This is a fan-made, unofficial addon.

If you are an author of another addon and have any concern about this project,
please open an issue — it will be addressed promptly.
