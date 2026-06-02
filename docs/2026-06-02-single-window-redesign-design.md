# Long Live Pets — Single-Window Redesign + Drag/Markers/Share + Auto Counter-Team Builder

**Date:** 2026-06-02
**Target version:** v0.6.0
**Status:** design — awaiting approval

## Goal

Make the UI smooth and intuitive by collapsing today's four surfaces (team
window, pet-browser window, hover tooltip, import/export popup) into **one
window**. Add **pet markers**, **drag-and-drop**, and **send-to-player**. Add a
brand-new feature Rematch lacks: an **auto counter-team builder** powered by an
**enemy-intel cache we build from the player's own battles**.

All original code. The bundled tdBattlePetScript (MIT) is unaffected.

---

## 1. The single window (3 panels)

One movable frame, three columns:

```
COLLECTION (left)        LOADED TEAM (center)        TEAMS (right)
- search box             - 3 slot buttons (drop      - grouped, ordered list
- type filter            - targets)                  - W-L, markers, tags
- Lv25 toggle            - team name field           - [+ group] [⚔ Build]
- name/ability search    - [Save] [Reload]           - drag to reorder/group
- scroll list            - Counter Coach line
- right-click: markers   - inline card strip (hover/click shows here)
```

Things that used to be separate windows become **inline**:
- **Pet card** → a strip along the bottom/center that fills on hover or click
  (reuses `PetCard:BuildLines`, rendered into fontstrings instead of a tooltip).
- **Import / Export / Backup** → an inline slide-down EditBox panel.
- **Share** → inline "send to ⟨name⟩" field on the selected team.

Retired: `UI/PetBrowser.lua` (separate window) and the `ShowText` popup in
`UI/MainWindow.lua`. Replaced by `UI/Main.lua` (the 3-panel window) plus small
panel files if it grows large. Minimap button (`UI/Minimap.lua`) stays.

### Modules touched / added
- `UI/Main.lua` — new 3-panel window (collection panel, loadout panel, teams
  panel, inline card, inline import/export/share). May split into
  `UI/panels/*.lua` if any single file gets large.
- `Core/Markers.lua` — marker storage + query.
- `Core/Comm.lua` — send/receive teams over addon messages.
- `Core/EnemyIntel.lua` — observe battles, store enemy comps per NPC.
- `Core/CounterBuilder.lua` — score collection vs a comp, pick best 3.
- Reuse unchanged: `Teams, Roster, Groups, Queue, Targets, Serialize, Battle,
  Types, Loadout, Init, Database, Integration/tdBattlePetScript`.

---

## 2. Drag-and-drop

- **Pet → slot:** a Collection row's `OnDragStart` puts the pet on a custom
  follow-cursor frame; a Loaded slot's `OnReceiveDrag`/click places it
  (`Roster:SlotPet`). Click-to-place is kept as a fallback (select slot, click
  pet).
- **Team → reorder / regroup:** drag a team row within the Teams panel; drop
  between rows reorders, drop onto a group header moves it.
- **Data:** add `team.order` (number, within its group/ungrouped bucket). New
  helpers: `Teams:Reorder(id, newIndex, groupID)` and `Teams:List` sorts by
  `(group order, team order, name)`. `Groups` gains `order` (already present).
- **Tested headlessly:** `Reorder`, group-move, and ordering in `List`. The
  cursor visuals are in-game only.

## 3. Pet markers

- 8 markers (the raid target icons: star, circle, diamond, triangle, moon,
  square, cross, skull) via `Interface\TargetingFrame\UI-RaidTargetingIcon_N`.
- Stored per **speciesID** in `db.markers[speciesID] = index` (account-wide, so
  it follows the pet).
- `Core/Markers.lua`: `Set(speciesID, index)`, `Get(speciesID)`, `Clear`,
  `texture(index)`.
- Shown as a small icon on Collection rows (and team-pet rows). Right-click a
  pet row → a marker chooser (small grid). Collection filter can show "marked".
- Tested: set/get/clear, and that `Roster:Filter({marker=n})` works.

## 4. Send-to-player

- `Core/Comm.lua` using `C_ChatInfo.RegisterAddonMessagePrefix("LLP")` and
  `SendAddonMessage`. A team is serialized with the existing `Serialize`
  (species + abilities), chunked if needed, sent WHISPER to the target name.
- Receiver reassembles, then sees a chat offer: `/llp accept` (or a popup
  button) to save the incoming team via `Teams:CreateImported`.
- Only works between two LLP users. Graceful no-op if the recipient lacks it.
- Tested: serialize→(simulated transport)→deserialize→CreateImported round-trip;
  chunk/reassemble logic.

## 5. Auto counter-team builder (NEW)

### 5a. Enemy intel (learn from battles)
- On `PET_BATTLE_OPENING_START`/`_DONE`, read the enemy side:
  `C_PetBattles.GetNumPets(enemyOwner)` and `GetPetType(enemyOwner, i)` (+
  species when available). The owner constant resolves via
  `Enum.BattlePetOwner.Enemy` with a fallback.
- Key by the **target NPC id** captured at battle start (reuse
  `Targets:CurrentNpcID`). Store
  `db.enemyIntel[npcID] = { name=, types={...}, species={...}, seen= }`.
- This is our own, original, player-built database — no third-party data.

### 5b. The builder (pure logic, fully testable)
`CounterBuilder:Build(enemyComp, ownedPets)` →
- For each owned pet, score against the comp:
  - `+3` for each enemy pet its **family is strong vs** (offense).
  - `+2` for each enemy pet whose attacks it **resists** (defense).
  - `+1` level-25, `+1` rare+ (tie-breakers).
- Greedily pick the 3 highest scorers that **maximize coverage** (prefer pets
  that answer not-yet-covered enemy pets), no duplicates.
- Return `{ picks = { {pet, reasons={...}}, ... }, covered = n/total }`.
- UI: **⚔ Build Counter** (enabled when the selected target/team has intel, or
  for the current target) shows the 3 picks + reasons; **Load** slots them.

### Why this is novel
Rematch organizes and recalls teams; it never *constructs* a counter from your
live-learned knowledge of a specific tamer with an explained rationale. This
does, and it gets smarter the more you play.

---

## Data model additions (`LongLivePetsDB`, schema → 3)
```
team.order      = <n>                 -- ordering within group
db.markers      = { [speciesID] = iconIndex }
db.enemyIntel   = { [npcID] = { name, types={t,...}, species={s,...}, seen } }
```
Migration: lazy defaults in `InitDB`; bump schema to 3. Existing teams get an
`order` on first sort.

## Testing
Extend the headless harness (currently 45 checks) to cover: team reorder/move &
ordered `List`; markers set/get/clear + marker filter; comm
serialize→reassemble→import round-trip; enemy-intel capture (mock battle); and
`CounterBuilder:Build` scoring/coverage on a known comp. Target: ~60 checks. UI
files must parse and build under the mock.

## Out of scope (future)
Flip-to-back lore card; journal-integrated mode; cross-faction send; a public
team-code directory.

## Risks
- Drag-and-drop and the inline card are the least testable (in-game only) — keep
  logic in tested modules, keep the view thin.
- `C_PetBattles` enemy-read API shape may need a small in-game tweak; capture is
  wrapped defensively so it can never error the addon.
