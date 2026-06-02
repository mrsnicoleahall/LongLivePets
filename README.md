# Long Live Pets 🐾

A pet **team manager** for World of Warcraft: save the pets you've slotted as a
named team, then reload that team in one click later. Built for **Midnight
(Interface 12.x)**.

> **Status: v0.1 — early but working foundation.** The core (save / load /
> rename / delete teams, slash commands, and a movable window) is implemented.
> More is on the roadmap below. This is honest about where it is — it is **not**
> a finished clone of any other addon.

This is an **original, independent project**. It is written from scratch and
contains **no code from Rematch or any other addon**. See
[NOTICE.md](NOTICE.md) for the full provenance and licensing statement.

---

## What it does today

- **Save the current team** — slot three pets the normal way, then save them
  under a name.
- **Load a team** — puts those exact pets (and their chosen abilities) back into
  your battle slots with one click.
- **Manage teams** — rename, delete, and list your saved teams.
- **A small movable window** plus a full set of `/llp` slash commands.
- **Optional tdBattlePetScript link** — tag a team with a script name (requires
  the separate, MIT-licensed tdBattlePetScript addon; see below).

## Commands

```
/llp                         open / close the window
/llp save <name>             save the slotted pets as a team
/llp load <name>             load a saved team
/llp delete <name>           delete a team
/llp rename <old> => <new>   rename a team
/llp script <team> => <name> link a tdBattlePetScript script to a team
/llp list                    list saved teams
```

## Install

1. Download / clone this repo.
2. Copy the **`LongLivePets`** folder into your AddOns folder:
   - **Windows:** `C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns`
   - **Mac:** `/Applications/World of Warcraft/_retail_/Interface/AddOns`
3. Enable **Long Live Pets** on the AddOns screen and log in.

> If you cloned the repo, copy the inner `LongLivePets` folder into AddOns (don't
> put the whole repo in there — WoW needs the folder that holds `LongLivePets.toc`
> to sit directly inside `AddOns`).

## tdBattlePetScript integration (optional)

Scripted battles are powered by **tdBattlePetScript** by *DengSir*, which is
**MIT-licensed**. Long Live Pets does not include it; install it separately if
you want scripts, then link a script to a team:

```
/llp script Aquatic Stomp => MyDungeonScript
```

Because tdBattlePetScript is MIT, it may also legally be bundled alongside this
addon as long as DengSir's copyright and license are kept intact.

---

## Roadmap (toward full parity)

- Groups / folders for teams, drag-and-drop ordering
- Target → team assignments and auto-suggestions
- Leveling queue
- Import / export team strings
- Richer pet browser and filters inside the window
- Tighter, two-way tdBattlePetScript integration (run the linked script on load)

Contributions and bug reports welcome.

## Development

Core logic has a headless test harness that mocks the WoW API so it can run
outside the game:

```
luajit Tests/headless.lua      # run from the repo root
```

It exercises save / load / rename / delete / script-linking, input guards, and
the window build path (19 checks). `Tests/` is not referenced by the TOC, so it
never loads in-game.

## License

MIT — see [LICENSE](LICENSE). © 2026 Nicole Hall.
