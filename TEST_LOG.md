# Long Live Pets — Test Log

A running checklist for verifying functionality in-game. Tick items as you test,
and note anything broken under **Issues found** at the bottom.

## Test environment

| Field | Value |
|---|---|
| Addon version | v0.9.2 (Alpha 2) |
| tdBattlePetScript | bundled (MIT) |
| WoW build | Midnight — bleeding-edge / beta (Interface 120000) |
| Realm | Garrosh |
| Faction / Race / Class | Horde · Tauren · Druid |
| Tester | Nicole |
| Date started | 2026-06-03 |

> Tip: turn on the error frame with `/console scriptErrors 1` (or use
> BugSack/!BugGrabber) so any Lua error shows up while you test.

---

## Checklist

Legend: `[ ]` untested · `[x]` pass · `[!]` issue (note it below)

### Window & layout
- [ ] `/llp` opens and closes the window
- [ ] Window drags/moves and stays put
- [ ] Three columns are framed and readable; center column content is centered
- [ ] Minimap button shows on the edge; click opens the window; drag repositions it
- [ ] No Lua errors on login / first open

### Collection (left)
- [ ] Pet list populates with owned pets
- [ ] Mouse-wheel scrolls the list
- [ ] Scrollbar drags the list
- [ ] Search box filters by name
- [ ] "name / ability" toggle → ability search finds pets by ability text (e.g. "bleed")
- [ ] Type dropdown filters by family
- [ ] Level dropdown: All / Level 25 / Leveling (1–24)
- [ ] Filter dropdown: Marked only / Rare+ only
- [ ] Counter dropdown: Strong vs / Tough vs a type narrows the list correctly
- [ ] Dropdown menus size to their text (no overflow)
- [ ] Hovering a pet shows its card (stats / type / rarity / source / flavor)
- [ ] Right-click a pet cycles its marker; marker icon shows on the row
- [ ] "Marked only" filter then shows just marked pets

### Loaded team (center)
- [ ] Clicking a slot makes it the active slot (highlight)
- [ ] Clicking a pet drops it into the active slot (no stuck-on-cursor)
- [ ] Dragging a pet onto a slot works (native cursor)
- [ ] Moves picker shows 3 ability slots across, 2 options each
- [ ] Clicking a move sets it; selected one is highlighted; locked shows unlock level
- [ ] Name box + Save creates a team
- [ ] Reload re-loads the current team

### Teams (right)
- [ ] Saved teams list; loaded team shows the green ">" marker
- [ ] Click a team loads it
- [ ] Right-click a team → Load / Rename / Edit note / Set+edit script / Test script / Delete
- [ ] Rename works; Delete works
- [ ] Edit note works; (n) tag appears
- [ ] ▲ / ▼ reorder a team within its group
- [ ] Win/loss shows after battles (auto), and `/llp record win|loss` works

### Groups
- [ ] "+ New Group" prompts for a name and creates it
- [ ] Empty groups show as headers
- [ ] Click a team to select, then click a group header to move it in
- [ ] Group header X deletes the group (teams kept, become ungrouped)
- [ ] Right-click group → Rename / Delete

### Leveling queue
- [ ] Teams / Queue toggle switches the right column
- [ ] `/llp queue add <slot>` adds the slotted pet
- [ ] Queue shows pets with level; X removes one
- [ ] A team slot flagged leveling (`/llp levelslot <team> <slot>`) fills from the queue on load
- [ ] A pet hitting 25 drops off the queue

### Targets
- [ ] `/llp target bind <team>` while targeting a tamer binds it
- [ ] `/llp target auto on` then targeting that tamer auto-loads the team

### Counter builder
- [ ] After fighting a tamer once, "Build Counter" suggests 3 pets with reasons
- [ ] "Load these picks" slots them
- [ ] `/llp counter <type>` prints advice

### Share / import / export
- [ ] Select a team, type a name, Send selected → recipient gets it (needs 2nd LLP user)
- [ ] `/llp accept` saves a received team
- [ ] Import/Export → backup string copies; pasting a string imports

### Battle scripts (tdBattlePetScript)
- [ ] tdBattlePetScript loads with no errors
- [ ] Right-click team → Set/edit script → enter a saved script's exact name
- [ ] Right-click team → Test script → reports "found"
- [ ] Load the team, start a pet battle, mash the tdBattlePetScript auto key (A) → script runs
- [ ] Script re-arms automatically when a battle opens

### Persistence
- [ ] Teams/groups/notes/scripts/markers survive a `/reload`
- [ ] They survive a full logout/login

---

## Issues found

| # | Area | What happened | Steps to reproduce | Error text (if any) |
|---|---|---|---|---|
| 1 |   |   |   |   |
| 2 |   |   |   |   |
| 3 |   |   |   |   |

---

## Notes / observations

-
