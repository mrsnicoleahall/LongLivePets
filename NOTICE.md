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

## Third-party software

- **tdBattlePetScript** by *DengSir* (Dengzhun Lu) — **MIT License.**
  Long Live Pets does **not** include tdBattlePetScript. It is an optional,
  separate addon you install yourself. Long Live Pets only provides its own
  original glue code (`Integration/tdBattlePetScript.lua`) that hands off to
  tdBattlePetScript's public interface when it is present.

  Because tdBattlePetScript is MIT-licensed, it may also be redistributed or
  bundled with this addon **provided DengSir's copyright notice and the MIT
  license text are retained**. If you choose to bundle it, include its original
  `LICENSE.md` unmodified.

## Trademarks / acknowledgements

World of Warcraft and the `C_PetJournal` API are the property of Blizzard
Entertainment. This is a fan-made, unofficial addon.

If you are an author of another addon and have any concern about this project,
please open an issue — it will be addressed promptly.
