# Long Live Pets 🐾

A pet **team manager** for World of Warcraft: save the pets you've slotted as a
named team, then reload that team in one click later. Built for **Midnight
(Interface 12.x)**.

> **Status: v0.4 — team manager + pet browser, in its own interface.**
> Everything below is implemented and covered by an automated test suite
> (37 checks). The companion battle-script engine (tdBattlePetScript) is now
> bundled.

This is an **original, independent project**. It is written from scratch and
contains **no code from Rematch or any other addon**. Long Live Pets uses its
own window — it does **not** modify or reskin Blizzard's pet journal. See
[NOTICE.md](NOTICE.md) for the full provenance and licensing statement, and the
acknowledgements at the bottom.

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
- **Pet browser** — our own window to search and filter your collection by
  name, type, level (25-only), and counters (Strong Vs / Tough Vs), then drop a
  pet straight into a battle slot. (`/llp pets`)
- **Counter helper** — `/llp counter <type>` tells you what beats an enemy type.
- **Minimap button + keybinding**, a movable window, and a full `/llp` command set.
- **Battle scripts** — the bundled, MIT-licensed **tdBattlePetScript** engine
  (by DengSir) is included; link a script to a team with
  `/llp script <team> => <name>`.

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
/llp pets                     open the pet browser
/llp find <text> | strong <type> | tough <type>
/llp counter <type>           counter advice for an enemy type
/llp record win|loss [team]
/llp minimap                  toggle the minimap button
/llp list
```

## Install

This download contains **two addon folders**: `LongLivePets` (this addon) and
`tdBattlePetScript` (the bundled MIT battle-script engine).

1. Download the release zip (or clone this repo).
2. Copy **both** `LongLivePets` and `tdBattlePetScript` into your AddOns folder:
   - **Windows:** `C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns`
   - **Mac:** `/Applications/World of Warcraft/_retail_/Interface/AddOns`
3. Enable them on the AddOns screen and log in. `/llp` to open.

> Each folder must sit **directly** inside `AddOns` (WoW needs to see
> `AddOns/LongLivePets/LongLivePets.toc`). If you already run a standalone copy
> of tdBattlePetScript, use only one to avoid a duplicate.
>
> Don't need scripts? You can install just `LongLivePets`.

## Battle scripts (tdBattlePetScript)

The bundled **tdBattlePetScript** engine is the work of **DengSir**, shared
under the **MIT License** — its `LICENSE.md` is kept intact in its folder. Long
Live Pets adds only its own original glue: link a script to a team with

```
/llp script Aquatic Stomp => MyDungeonScript
```

and it hands off to tdBattlePetScript when that team loads.

---

## Roadmap

Done: team manager (groups, notes, W/L, targets, queue, import/export) and an
original pet browser with filters. Still ahead:

- Pet card tooltip with stats, lore, and a flip-to-back view
- Pet markers (star / diamond / moon, etc.)
- Ability-text search ("list pets that cause Bleed")
- Drag-and-drop reordering of teams and groups
- Send-a-team-to-another-player (addon comms)
- Tighter two-way tdBattlePetScript integration (run the linked script on load)

Contributions and bug reports welcome.

## Development

Core logic has a headless test harness that mocks the WoW API so it can run
outside the game:

```
luajit Tests/headless.lua      # run from the repo root
```

It exercises teams, groups, notes, win/loss, import/export/backup, targets, the
leveling queue, the roster filters, and every window build path (37 checks).
`Tests/` is not referenced by the TOC, so it never loads in-game.

## Open source

Long Live Pets is **free and open source** under the **MIT License** — use it,
read it, fork it, ship your own changes. The only third-party code in the
project is the bundled **tdBattlePetScript** engine, which is itself MIT and
keeps its own license file. Pull requests welcome.

## Acknowledgements

- 🎩 **Hat tip to Gello**, the author of **Rematch** — the addon that defined
  what great pet-team management feels like and inspired this project. Long Live
  Pets is an independent, clean-room implementation and contains **none** of
  Rematch's code; it simply admires the idea. All credit for Rematch is Gello's.
- 🙏 **DengSir** (Dengzhun Lu), author of **tdBattlePetScript** — the battle
  scripting engine bundled here under the MIT License. The engine is DengSir's
  work; we only add an original integration layer.
- 🐾 World of Warcraft and the `C_PetJournal` API are property of Blizzard
  Entertainment. This is an unofficial, fan-made addon.

## License

MIT — see [LICENSE](LICENSE). © 2026 Nicole Hall.
The bundled `tdBattlePetScript/` retains its own MIT license (© DengSir).
