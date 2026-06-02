# Long Live Pets 🐾

A pet **team manager** for World of Warcraft: save the pets you've slotted as a
named team, then reload that team in one click later. Built for **Midnight
(Interface 12.x)**.

> **Status: v0.3 — the team-management core is feature-complete.** Everything
> below is implemented and covered by an automated test suite (29 checks). The
> deep *collection-browser* layer (full pet roster UI, pet card, ability search,
> markers, send-to-player) is still on the roadmap — see the bottom.

This is an **original, independent project**. It is written from scratch and
contains **no code from Rematch or any other addon**. See
[NOTICE.md](NOTICE.md) for the full provenance and licensing statement.

---

## Features

- **Teams** — save the slotted pets (with their chosen abilities) as a named
  team and reload them in one click. Rename, delete, list.
- **Groups** — organize teams into folders; the window shows them grouped.
- **Notes** — attach a note to any team.
- **Win/loss record** — per-team W-L, auto-tracked at the end of a battle (plus
  a manual `record` command).
- **Targets** — bind a team to a tamer/NPC; optionally auto-load it when you
  target them.
- **Leveling queue** — queue pets to level; flag a team slot as a "leveling"
  slot and it auto-fills from the queue. Maxed pets drop off automatically.
- **Import / export / backup** — share a team as a compact string, or back up
  every team at once; paste to import.
- **Counter helper** — `/llp counter <type>` tells you what beats an enemy type.
- **Minimap button + keybinding**, a movable window, and a full `/llp` command set.
- **Optional tdBattlePetScript link** — tag a team with a script name (requires
  the separate, MIT-licensed tdBattlePetScript addon; see below).

## Commands

```
/llp                          open / close the window
/llp save <name>              save the slotted pets as a team
/llp load <name>              load a team
/llp reload                   reload the current team
/llp rename <old> => <new>    rename a team
/llp delete <name>            delete a team
/llp note <team> => <text>    set/clear a team note
/llp group add <name>         create a group
/llp group set <team> => <group>   move a team into a group
/llp group clear <team> | rename <old> => <new> | delete <name>
/llp queue add <slot> | list | clear      manage the leveling queue
/llp levelslot <team> <slot> [off]        mark a slot as a leveling slot
/llp target bind <team> [npcID] | unbind | auto on|off
/llp export <team>            show a shareable string
/llp import [string]          import a team or backup
/llp backup                   export all teams
/llp counter <type>           counter advice for an enemy type
/llp record win|loss [team]
/llp minimap                  toggle the minimap button
/llp list
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

## Roadmap (the deep collection-browser layer)

The team-management core is done. What's left is the big pet-collection UI:

- A full pet-roster browser inside the window with live filters (Strong Vs /
  Tough Vs / level / stats) and ability text search
- Pet card tooltip with stats, lore, and the flip-to-back view
- Pet markers (star / diamond / moon, etc.)
- Drag-and-drop reordering of teams and groups
- Send-a-team-to-another-player (addon comms)
- Journal-integrated mode (replace the Blizzard pet journal panel)
- Tighter two-way tdBattlePetScript integration (run the linked script on load)

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
