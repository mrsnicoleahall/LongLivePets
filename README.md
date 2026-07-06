# Long Live Pets 🐾

A pet **team manager** for World of Warcraft: save the pets you've slotted as a
named team, then reload that team in one click later. Built for **Midnight
(Interface 12.x)**.

> **Status: v2.0 — full UI redesign.** A calm dark theme with a single gold
> accent, **custom circular pet-type icons**, a 3-card team-stat strip,
> zebra-striped collection, one-row filters, and right-click management (no
> per-row button clutter). Breed data refreshed to cover current-era pets. One
> window with notes, scripts, a leveling-queue tab, and battlescript hand-off.
> Open with `/llp` or the minimap button.

This is an **original, independent project**. It is written from scratch and
contains **no code from Rematch or any other addon**. Long Live Pets uses its
own window — it does **not** modify or reskin Blizzard's pet journal. See
[NOTICE.md](NOTICE.md) for the full provenance and licensing statement, and the
acknowledgements at the bottom.

---

## Features

- **Clean, themed UI** — calm dark panels with a single gold accent, custom
  circular pet-type icons, zebra-striped lists, and a team-stat strip. Built to
  stay readable, not cluttered.
- **One 3-panel window** — Collection · Loaded Team · Teams, all visible at
  once. The pet card, import/export, and share are inline — no separate windows.
- **Drag-and-drop** — drag a pet onto a slot; drag teams to reorder (or
  right-click a team → Move up/down). Click also works everywhere.
- **Pet markers** — right-click a pet to tag it with a raid icon (★/◆/🌙/…);
  filter the collection to just marked pets.
- **Send-to-player** — select a team, type a name, **Send** — it arrives for any
  other Long Live Pets user to save.
- **Auto counter-team builder** — Long Live Pets *learns* each tamer's pets from
  your battles, then **⚔ Build Counter** picks your best 3 against them (by the
  type wheel) and explains why, with one-click load. Rematch can't do this.
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
- **Pet browser** — filter your collection with **dropdowns** (Type, Level, and
  a More filter for marked/rare), plus name or ability-text search. Click a pet
  to slot it.
- **Move selection** — pick each loaded pet's abilities right in the window:
  the center panel shows all 3 ability slots × 2 options; click to choose
  (locked options show their unlock level).
- **Pet cards** — hover any pet in the browser for a card with its stats
  (health / power / speed), type, rarity, source, and flavor text.
- **Ability search** — flip the browser's search to "ability" mode (or use
  `/llp find ability <text>`) to list pets with a matching ability name or
  description — e.g. find everything that causes *Bleed*.
- **Counter helper** — `/llp counter <type>` tells you what beats an enemy type.
- **Minimap button**, a movable window, and a full `/llp` command set.
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
/llp build                    auto-build a counter team for your target
/llp send <team> => <player>  send a team to another LLP user
/llp accept                   save a team someone sent you
/llp record win|loss [team]
/llp minimap                  toggle the minimap button
/llp list
```

## Install

📦 **Full step-by-step guide: [INSTALL.md](INSTALL.md).** Quick version below.

This download contains **two addon folders**: `LongLivePets` (this addon) and
`tdBattlePetScript` (the bundled MIT battle-script engine).

1. On the [latest release](https://github.com/mrsnicoleahall/LongLivePets/releases/latest),
   download the **`LongLivePets-x.y.z.zip`** asset — **not** "Source code (zip)".
   (The source zip names its folder after the version and nests `tdBattlePetScript`
   inside, so WoW won't load it.) Unzip it.
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

Done: the single 3-panel window, drag-and-drop, pet markers, send-to-player, the
auto counter-team builder, plus the full team manager (groups, notes, W/L,
targets, queue, import/export), pet browser with filters, hover cards, and
ability-text search. Still ahead:

- A flip-to-back lore view on the pet card
- Cross-faction / cross-realm sending
- A public team-code directory
- Tighter two-way tdBattlePetScript integration (run the linked script on load)

Contributions and bug reports welcome.

## Development

Core logic has a headless test harness that mocks the WoW API so it can run
outside the game:

```
luajit Tests/headless.lua      # run from the repo root
```

It exercises teams (incl. reorder), groups, notes, win/loss, import/export/backup,
targets, the leveling queue, roster + ability + marker filters, the pet card,
send-to-player chunk/reassemble, enemy-intel capture, the counter-team builder,
and every window build path (67 checks). `Tests/` is not referenced by the TOC,
so it never loads in-game.

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
