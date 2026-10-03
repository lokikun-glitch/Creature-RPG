# Creature RPG (working title)

An original top-down creature-collecting RPG built with Godot 4. The current target is **Milestone 001: Starter Town + Starter Creature Selection**.

Developed and tested on **Godot 4.7.2**. Earlier 4.x versions are untested.

## Run

Open `project.godot` in Godot and press **F5**. The game opens on the title screen.

| Action | Keys |
|---|---|
| Menus: move / choose / back | W/S or Up/Down (Left/Right in dialogs) · E/Enter/Space · Esc. The mouse works too. |
| Move (8 directions) | WASD / arrow keys |
| Interact (whatever you are facing) | E |
| Advance dialogue | E / Space / Enter |
| Starter screen: browse / choose / back | Left/Right or A/D · E/Enter/Space · Esc |
| Pause menu (while exploring) | Esc |
| Battle: choose / navigate / back | E/Enter/Space · arrows or WASD · Esc (messages advance on their own; E skips ahead). The mouse works too. |

Esc opens the pause menu (Continue, Save Game, Settings, Return to Title), but only while you're free to walk around. It won't open during dialogue, menus, map transitions or battles.

### Title screen

- **Continue** loads your save and puts you back exactly where you saved, on the same map and facing the same way, with your party and story progress. It's greyed out when there's no save. If the save can't be read, a "Save data could not be loaded." message appears and Continue stays disabled. The file is never deleted or changed when this happens.
- **New Game** starts in Fernhollow Town, in front of the player's house, with an empty party and no story progress. If a save exists, it first asks "Start a new game? This will overwrite your existing save." The default answer is NO; only YES deletes the old save.
- **Settings:** volume options are placeholders until the game has sound.

### Saving

The game saves itself at checkpoints and shows a small "Game saved." notice that doesn't interrupt play:

- after choosing your starter;
- after every battle, once you're back in the world (win, loss, escape or capture);
- after resting in your bed (only if anything was actually healed);
- after entering a new map, once the transition has finished;
- after changing the lead, reordering the party, moving creatures to or from storage, or renaming;
- after buying something;
- when you return to the title from the pause menu.

You can also save at any time with Esc → Save Game. Wild encounters and battles in progress are never saved.

A save holds your map, position and facing; story flags; your party (in order, with nicknames) and which creature leads; your items; your Coins; and any creatures in storage.

| | Location |
|---|---|
| Save file | `user://savegame.json` |
| On Windows | `%APPDATA%\Godot\app_userdata\Creature RPG (Working Title)\savegame.json` |

## Development

### Forcing a new game

The `--new-game` user argument skips the title screen and starts a clean game. Unlike the menu's New Game, it leaves the existing save file alone until the game next saves.

- **Command line:** `godot --path . -- --new-game`
- **In the editor:** set Project Settings → Editor → Run → Main Run Args to `-- --new-game`

### Forcing a wild encounter (F6)

Debug builds only; exported release builds ignore it.

- **Standing in tall grass:** F6 starts a wild encounter immediately.
- **Anywhere else:** F6 makes the next step taken in tall grass trigger one.
- **From code or tests:** `EncounterManager.force_next_encounter()`, or `force_next_encounter_species(id, level)` to choose exactly which registered species appears and at what level. These are code hooks only; nothing in the player's UI exposes them.

### Tests

```
godot --headless --path . res://tests/smoke_test.tscn
```

`smoke_test.tscn` runs a small `tests/test_runner.gd`, which loads the real test script (`tests/smoke_test.gd`) and guarantees the process always ends:

- **Script fails to parse:** prints `HARNESS FAILED: test script did not load` and exits with code **100**.
- **Process exceeds its time limit:** prints `HARNESS FAILED: timeout` with the last section that was running, and exits with code **99**. The limit is `--test-timeout=<seconds>` (default 3600); each relaunch stage gets 300.
- **Otherwise:** the exit code is the number of failed checks, so 0 means everything passed.
- **Self-check:** the suite verifies both failure modes by launching a deliberately broken script and a script that never finishes.

The test loads the real `main.tscn` and drives it with simulated keyboard and mouse input. It covers:

- the title screen, New Game, Continue and corrupted saves
- movement, collision and map transitions
- interaction and dialogue
- creature data, `CreatureFactory` and `PartyManager`
- the starter-selection flow
- Route 01, tall grass and wild encounters
- battles, items, capture, switching, storage and save version 2 / migration
- the party screen, storage terminal, nicknames, lead and order, Coins and the shop, resting, NPC collision, Route 01's field camp, and save version 3 / migrations

Encounter randomness is deterministic in tests:

- the test seeds `EncounterManager.rng`;
- probabilities are checked statistically on that fixed seed;
- in-world encounters are forced, or use a 0% or 100% rate.

Checks that need a real quit and relaunch start **separate Godot processes**:

| Stage | Checks |
|---|---|
| `continue_flamkit` | Run right after choosing the starter: Continue restores Flamkit. Then New Game over the save, and choose Aquaphin. |
| `continue_aquaphin` | Continue restores only Aquaphin. |
| `battle_fresh` | Continue, then a whole battle; the result is autosaved. |
| `new_game_arg` | `--new-game` skips the title and leaves the save alone; no encounters before a starter. |
| `capture_start` → `capture_continue` → `capture_verify` | New Game → starter → catch a Pebblit → quit. Then Continue: check the caught creature exactly, switch to it and win, fill the party to 6, catch a Cindrake into storage → quit. Then a final reload checks the party, storage, items and active creature. |
| `migrate_v1` → `migrate_verify` | Load a real version 1 save, check nothing changed and it received the starting items and 500 Coins, save it as version 3, and reload that. |
| `migrate_v2` → `migrate_v2_verify` | Load a real version 2 save (3 orbs, a stored creature, lead in slot 2): check those are kept exactly and 500 Coins are added, save it as version 3, and reload that. |
| `e2e_start` → `e2e_verify` | The whole Phase 12 loop: New Game → starter → save → party screen (rename to "Ember") → Route 01 battle and catch → back to Fernhollow → change the lead and reorder → rest → buy 2 Capture Orbs → deposit and withdraw at the storage terminal → reorder again → save → quit. Then relaunch, Continue and check the map, position, facing, party order, lead, nickname, HP, level, EXP, moves, status, storage, items, Coins and story flags exactly. |
| `safety_start`, then `safety` × 5 (`run`, `lose`, `heal`, `manual`, `verify`) | Save-safety chain: New Game, Flamkit, save, beat a wild Tideclaw and level up, quit. Then repeatedly launch, Continue, check that the creature, level, EXP, HP, map, position and story state all match, and do the next scenario. |

Simulated key presses wait until Godot has actually delivered them (`delivered()`), not just for physics frames: after a long blocking relaunch the engine catches up by running several physics frames per rendered frame, and a check could otherwise run before the key arrived.

The test prints PASS/FAIL per check and exits with the number of failures. It uses its own save file (`user://test_savegame.json`), never your real one.

To save screenshots, run with a window instead of `--headless` and add `-- --shots=<dir>` at the end of the command. Exclude `tests/` when you set up export presets.

## Structure

```
main/main.tscn          Main → World (persistent Player + current map) + UI (banner, dialogue box)
scripts/core/           GameSession (title/new game/continue), SceneRouter (fades + map changes),
                        GameState (saved flags), Direction helper
scripts/world/          World, GameMap, SpawnPoint, MapTransition, Building, SignPost, CharacterSprite,
                        HealPoint (bed), ShopCounter, StorageTerminal
scripts/player/         Player controller, PlayerCamera (map-bounded)
scripts/interaction/    Interactable, InteractionManager, InteractionPrompt
scripts/dialogue/       DialogueManager autoload, DialogueData, DialogueLine
scripts/creatures/      CreatureSpecies, CreatureInstance, CreatureFactory, CreatureDatabase autoload,
                        CreatureStats (formula), CreatureProgression (EXP/levels), MoveData, ElementData, StarterSet
scripts/party/          PartyManager autoload (party + active creature), CreatureStorage,
                        CreatureManagement (rules: lead, order, deposit/withdraw, rename, rest)
scripts/economy/        Wallet (Coins), Shop (buying rules)
scripts/items/          ItemData, ItemCatalog (static registry), Inventory
scripts/save/           SaveManager autoload
scripts/events/         Story events (StarterSelectionEvent)
scripts/npc/            NPC
scripts/encounters/     EncounterManager autoload, EncounterZone, EncounterTable, EncounterEntry, WildEncounter
scripts/battle/         BattleManager autoload (rules), BattleCalculator, BattleAI, BattleContext, BattleEvent,
                        BattleSide, BattleMessages, BattleScene + BattleStatusPanel (presentation)
scripts/ui/             TitleScreen, PauseMenu, SettingsPanel, ChoiceDialog, SaveNotice, MapNameBanner, DialogueBox,
                        StarterSelectionScreen, StarterCard, PartyScreen, StorageScreen, ShopScreen,
                        CreatureDetailPanel, NicknameDialog, ConfirmPrompt, WorldMenu (base), MenuList,
                        CreatureRow, UiStyle
scenes/world/maps/      Town, research lab, player's house, Route 01
scenes/world/objects/   Building, tree, rock, sign post, map transition, bed (heal point), shop counter,
                        storage terminal, tent, campfire, log seat, survey marker
scenes/encounters/      encounter_zone.tscn (tall grass)
scenes/battle/          battle_scene.tscn, battle_status_panel.tscn
scenes/interaction/     interactable.tscn (the reusable component)
data/encounters/        One EncounterTable .tres per area (route_01.tres)
data/creatures/         One CreatureSpecies .tres per species (auto-registered by id)
data/moves/             One MoveData .tres per move (auto-registered by id)
data/elements/          ElementData .tres (name, UI colour)
data/starters/          StarterSet offered by Professor Elian
data/dialogue/          Dialogue .tres files
assets/creatures/       Creature sprites
data/items/             One ItemData .tres per item (capture_orb.tres)
tests/                  test_runner.gd (entry point, fails loudly) + smoke_test.gd
```

Autoloads, in load order: `SceneRouter`, `DialogueManager`, `GameState`, `CreatureDatabase`, `PartyManager`, `SaveManager`, `GameSession`, `EncounterManager`, `BattleManager`.

## How the world fits together

- **The player is never inside a map.** `World` keeps one `Player` and swaps map scenes underneath it.
- **Changing maps:** anything calls `SceneRouter.go_to(map_path, spawn_id)`. Destinations are named `SpawnPoint`s.
- **Maps** use the `GameMap` script and have `Ground` and `Obstacles` `TileMapLayer`s, where tiles in `Obstacles` have collision. Camera limits come from the painted area of `Ground`.
- **Player control locks:** transitions and dialogue each call `player.add_control_lock(name)` / `remove_control_lock(name)`. The player can move only when no locks are held.
- **Physics layers:** 1 world, 2 player, 3 npc, 4 interactable, 5 triggers.

## Interaction

```
Player (movement, facing; sends the request on E)
  └─ InteractionManager — each physics frame, finds the Interactable straight ahead
        ↓ interact(player)
     Interactable (Area2D on layer 4) — emits `interacted`, plays its `dialogue` if set
        ↓
     The owner's behaviour (NPC turns to face you, Building enters or reports "locked", …)
```

How the target is chosen:

1. Snap the player's facing to up/down/left/right, using the same rule the sprite uses.
2. Run a shape query with a thin 6 × 32 px probe directly ahead of the player, on the interactable layer only.
3. Keep only candidates that are:
   - ahead of the player;
   - within their own `interaction_distance`;
   - inside a 45° cone, so anything beside the player is ignored;
   - visible: a ray on the world layer from the player to the candidate must hit nothing, ignoring the candidate's own body.
4. Pick the winner: highest `interaction_priority` first, then whichever is most directly ahead and closest.

The "E" prompt shows exactly the target that pressing E would use.

### Adding an interactable NPC

1. Instance `scenes/npc/npc.tscn` under the map's `Objects/NPCs`.
2. Set `display_name`, `sprite_sheet` and `facing`.
3. Create a dialogue in `data/dialogue/` (right-click → New Resource → `DialogueData`). Set `speaker`, then add `DialogueLine`s to `lines`.
4. Assign it to the NPC's `dialogue`. An NPC with no dialogue can't be talked to.
5. Optional: set `alternate_dialogue`, which is said instead once the GameState flag named in `alternate_flag` (default `starter_selected`) is true. That's how villagers say something different after you have a partner.

NPCs turn to face whoever talks to them and keep that facing.

**NPC collision.** Characters are drawn about 19 px above their feet, 3 px below and 5 px to each side, so a feet-only collision let the player walk up until their head covered most of an NPC. The NPC's body shape (12 × 36 px, centred 3 px above the feet) is instead the area where another character's feet would make the two sprites overlap. The player now stops just touching an NPC from every side, can still walk past beside them, and the NPC's `Interactable` reaches 26 px so you can talk from any of those spots. The player's own collision, walls, doors and other objects are unchanged.

### Adding a sign

Instance `scenes/world/objects/sign_post.tscn` and assign a `DialogueData` with an empty `speaker` to its `dialogue`. Any readable object can reuse `SignPost` with its own sprite, like the campfire and survey marker on Route 01.

### Configuring a door (Building)

| Goal | Settings |
|---|---|
| Walk in to enter (like the lab) | `door_target_map`, `door_target_spawn`; `enter_on_interact` off |
| Face the door and press E (like the player's house) | as above, plus `enter_on_interact` on |
| Locked | leave `door_target_map` empty. E shows `locked_dialogue` ("The door is locked." by default) |
| Spot just outside the door | `exit_spawn_id`, so other maps can send the player there |

### Anything else (chests, items, quest objects)

Add an `interactable.tscn` instance as a child of the object, then either give it a `dialogue` or connect its `interacted(actor)` signal to your script. Use `interaction_priority`, `interaction_distance` and `prompt_offset` to tune it.

## Creatures

- **Species vs. instance.**
  - A `CreatureSpecies` (`data/creatures/*.tres`) is shared, read-only data: name, description, element, role, base stats, starting moves, sprite, evolution info.
  - A `CreatureInstance` is one owned creature: uid, species id, nickname, level, XP, current HP, move ids, status. It never copies species data; it looks it up through `CreatureDatabase`.
- **Stats** are always calculated in `CreatureStats.calculate()`:
  - max HP = base HP + level × 2
  - every other stat = base + level

  Nothing else (UI included) calculates stats.
- **`CreatureFactory.create_from_species(species, level)`** is the only way new owned creatures are made. It sets the level, a unique id, full HP and the starting moves (at most 4). Wild, gift, trainer and caught creatures should use it too.
- **`PartyManager`** holds up to 6 creatures with no gaps between them: `add_creature()`, `remove_creature()`, `get_creature(slot)`, `get_party()`, `get_size()`, `has_space()`, `clear()`.
- **Adding a species:** create a `CreatureSpecies` resource in `data/creatures/` with a unique `id`. `CreatureDatabase` registers it automatically.
- **Validation:** `CreatureDatabase` checks every element, move and species before registering it. Anything with a problem is reported (`push_error` and `CreatureDatabase.load_problems`) and skipped, so broken data fails at startup instead of crashing a battle. The checks:
  - unique, non-empty ids;
  - a display name;
  - a registered element;
  - a sprite;
  - positive base stats;
  - 1–4 starting moves that are all registered;
  - move power ≥ 0 and accuracy 1–100.

### Roster

| Species | Element | Role | HP / Atk / Def / Spd | Starting moves |
|---|---|---|---|---|
| Flamkit | Ember | Offensive | 45 / 60 / 40 / 70 | Tackle, Ember |
| Aquaphin | Tide | Balanced | 55 / 50 / 50 / 55 | Tackle, Splash |
| Mossaur | Verdant | Defensive | 65 / 45 / 65 / 35 | Tackle, Vine Whip |
| Pebblit | Neutral | Balanced | 50 / 48 / 52 / 42 | Tackle, Quick Jab |
| Cindrake | Ember | Offensive | 48 / 65 / 38 / 62 | Tackle, Ember, Flame Burst |
| Rivulet | Tide | Balanced | 52 / 52 / 48 / 60 | Tackle, Splash, Quick Jab |
| Thornling | Verdant | Offensive | 50 / 58 / 45 / 55 | Tackle, Vine Whip, Leaf Cutter |
| Brambleox | Verdant | Defensive | 72 / 50 / 68 / 28 | Tackle, Vine Whip |
| Tideclaw | Tide | Offensive | 54 / 63 / 42 / 58 | Tackle, Splash, Water Pulse |

| Move | Element | Power |
|---|---|---|
| Tackle | Neutral | 40 |
| Quick Jab | Neutral | 30 |
| Ember | Ember | 40 |
| Flame Burst | Ember | 55 |
| Splash | Tide | 20 |
| Water Pulse | Tide | 50 |
| Vine Whip | Verdant | 45 |
| Leaf Cutter | Verdant | 50 |

### Replacing a creature's sprite

1. Put the new image in `assets/creatures/`, e.g. `flamkit.png`. Keep the art front-facing and centred. The starter cards show it at its native size in a 32×34 slot, so resize the slot in `scenes/ui/starter_card.tscn` if the new art is bigger.
2. Open `data/creatures/flamkit.tres` in the Inspector and drag the new texture onto **Sprite**. Alternatively, overwrite the existing PNG with the same file name and nothing needs re-linking.
3. Add the asset's author, source and license to `ASSET_LICENSES.md`.

No code refers to creature images directly, so nothing else needs to change.

## Starter selection and saving

```
Elian (plain NPC) → intro dialogue → DialogueManager.dialogue_finished
  → StarterSelectionEvent (node in research_lab.tscn) opens StarterSelectionScreen   [player control locked]
  → screen reports only "species X chosen"
  → CreatureFactory → PartyManager.add_creature → GameState.starter_selected = true → SaveManager.save_game()
  → screen closes, control returns → Elian's "{creature} has joined your team!" dialogue
```

`StarterSelectionEvent` also picks which dialogue Elian uses: the intro, or "You've already chosen your companion" once `starter_selected` is true.

**The save file** is JSON with these sections:

| Section | Contents |
|---|---|
| `world` | map, position, facing |
| `game_state` | flags, e.g. `starter_selected`, `starter_species` |
| `party` | one entry per creature, in party order: uid, species_id, nickname, level, experience, current_hp, moves, status |
| `active_index` | the lead's party slot |
| `inventory` | item id → quantity |
| `storage` | stored creatures, same format as `party` |
| `currency` | Coins, a whole number |
| `version` | save format version |

No Resource objects are saved; creatures are rebuilt from ids when loading, and invalid values are clamped. On load, flags and the party are restored *before* the map loads, because maps read flags as soon as they appear.

**Save versions.** `SaveManager.CURRENT_SAVE_VERSION` (currently **3**) is written into every save, and `MIN_SUPPORTED_SAVE_VERSION` is the oldest version that can still be read. When the format changes:

1. Bump `CURRENT_SAVE_VERSION`.
2. Add a step to `SaveManager._migrate()` that upgrades the previous version.

Saves from newer builds, or older than the minimum, are rejected with a message. They are never deleted or modified.

| Version | Contents |
|---|---|
| 1 (Phases 5–10) | `world`, `game_state`, `party` |
| 2 (Phase 11) | Adds `inventory` (item id → quantity), `storage` (creatures, same format as the party) and `active_index` (the active party slot). |
| 3 (Phase 12) | Adds `currency` (Coins). |

Older saves are upgraded in memory, one step at a time, before they are validated or applied:

- `_migrate_1_to_2()`: the New Game starting items (5 Capture Orbs), an empty storage, and active slot 0;
- `_migrate_2_to_3()`: 500 Coins (the New Game amount); inventory, storage and the active slot are kept exactly;
- nothing else is touched, and the file itself only becomes version 3 the next time the game saves.

**Validation.** `SaveManager.read_save()` checks the save without changing any game state:

- the file exists;
- it's valid JSON;
- the version is a whole number in the supported range;
- `world`, `game_state`, `party`, `inventory`, `storage`, `active_index` and `currency` exist with the right types;
- inventory quantities, the active index and `currency` are whole numbers ≥ 0;
- the party has at most 6 creatures, and every party and storage entry looks like a saved creature (`CreatureInstance.validate_save_data()`: a species id, whole-number level ≥ 1, HP and EXP, text fields that are text, and a list of move ids).

A save that fails any of these is reported as damaged and nothing from it is applied.

Unknown item ids, like unknown species, are skipped when the save is applied.

Per-field clamping and unknown-id handling happen afterwards, while the data is applied.

## Save checkpoints

```
pause menu / starter event / bed / battle end / map change
  → GameSession.save_now() or request_save(reason)
  → SaveManager.save_game() → world + GameState + PartyManager → validate → temp file → savegame.json
```

- **Nothing writes JSON except `SaveManager`.**
- **`GameSession.save_now(reason)`** saves immediately when the game is settled: playing, a map loaded, no transition, encounter or battle running.
- **`request_save(reason)`** is the autosave checkpoint. It saves now if that's safe; otherwise it remembers the request and saves when the current transition or battle has finished.
- **`GameSession.game_saved(reason)`** fires after every save. The `SaveNotice` shows "Game saved.", and the reason (`manual`, `starter_selected`, `battle_victory`, `rested`, `map_entered`, `lead_changed`, `party_reordered`, `creature_deposited`, `creature_withdrawn`, `nickname_changed`, `purchase`…) helps when debugging.
- **New checkpoints** call `GameSession.request_save(&"why")`; nothing else is needed.
- **Validation:** `SaveManager.save_game()` checks what it's about to write with the same validation used when loading, and refuses to write invalid data.
- **Format:** version 3 since Phase 12 (see Save versions); version 1 and 2 saves still load.

## Pause menu

`PauseMenu` (Esc while exploring) only talks to `GameSession`:

| Option | What it calls |
|---|---|
| Continue | — (closes the menu) |
| Creatures | opens the `PartyScreen` (see Managing creatures) |
| Save Game | `save_now()` |
| Settings | the shared `SettingsPanel`, the same one the title screen uses |
| Return to Title | asks first, then `save_now()` → `return_to_title()` |

While it's open, the player holds a `pause` control lock: no movement or interaction, and NPCs and encounters are frozen. The engine itself isn't paused, so the menu stays responsive.

## Managing creatures, Coins and the shop

**Rules live in `CreatureManagement`** (a static class, not an autoload). Screens call it and show the message it returns; every successful change is saved through `GameSession.request_save()`.

| Action | Rule |
|---|---|
| Set as lead | The slot must hold a creature that isn't fainted and isn't already the lead. The lead fights first in the next battle; if it has fainted by then, the first creature that can fight goes instead, and with nobody able to fight there are no encounters. |
| Move (reorder) | `PartyManager.move_creature(from, to)` moves one creature and shifts the rest. The lead stays the same creature: its index is looked up again afterwards, not kept as a number. |
| Deposit (party → storage) | The party can't become empty, and the last creature that can fight can't leave. If the lead is deposited, the first remaining creature that can fight becomes the lead. The creature is moved unchanged. |
| Withdraw (storage → party) | Needs a free party slot; the creature joins at the end, unchanged. |
| Rename | 1–16 characters after trimming surrounding spaces, no control characters, any other Unicode. Only `nickname` changes, never the species. A refused name leaves the old one. |
| Rest | `rest_all()` restores every owned creature (party and storage) to full HP with no status. Nothing else changes. Returns whether anything was healed. |

**Party screen** (Esc → Creatures): all six slots straight from `PartyManager`: nickname, species, level, HP, element, status (OK / Fainted) and a LEAD tag; "Empty" for free slots. Choose a creature for SUMMARY, SET AS LEAD, MOVE (then pick the target slot) or CANCEL. It lives inside the pause menu, so the pause lock covers it, and it's separate from the battle CREATURE menu.

**Summary** (`CreatureDetailPanel`, shared by the party and storage screens): nickname, species, element, role, level, HP, EXP towards the next level, status and moves. No UIDs or internal ids. RENAME opens `NicknameDialog` ("Enter nickname:"), a normal text field: Enter or OK confirms ("Nickname changed to "Ember"."), Esc or CANCEL backs out.

**Storage terminal** (in the Research Lab): E → "Access Creature Storage?" → `StorageScreen`, with PARTY and STORAGE tabs (Left/Right or click). Rows show the same details as the party screen; long lists scroll six at a time. An empty storage says "No creatures in storage."

**Coins and the shop.** `Wallet` (owned by `GameSession`, like the inventory) holds Coins, an original in-game currency. New Game starts with 500; choosing a starter doesn't change it. The Fernhollow Market stall on the plaza (`ShopCounter`; Dara stands behind it) sells Capture Orbs for 100 each. Prices are `ItemData.price`; `Shop` checks funds and changes Coins and items together or not at all; `GameSession.buy_item()` makes the purchase and saves. Choose an amount with Left/Right (±1) and Up/Down (±10), up to what you can afford; with too little money: "Not enough Coins."

**Resting.** The bed asks "Rest and restore your creatures?" (default NO). YES heals the party and storage: "Your creatures are fully rested." and an autosave. If everyone is already healthy: "Your creatures are already fully rested.", and nothing is saved.

**Modal screens and locks.** World menus (`ConfirmPrompt`, `StorageScreen`, `ShopScreen`) extend `WorldMenu`, which holds a player control lock while open: no movement, no interaction, and no pause menu underneath. The key press that opened a menu is never treated as input to it.

## Route 01

Route 01 keeps its size, spawn point, exits, grass zones and encounter table. Phase 12 changes:

- **Field camp** (landmark, an optional dead end north of the west junction): a tent, campfire, log seat and a lab survey marker by the pond, with Researcher Wren, who explains element matchups. A short dirt path now leads there from the junction.
- **Junction sign:** "North: Field Camp / East: Lookout and north gate / South: Fernhollow Town".
- **Grass edges:** every `EncounterZone` draws a dark outline, so it's clear where encounters can happen.
- **NPC roles:** the Young Trainer gives a catching tip once you have a partner; the Hiker points out the camp. In Fernhollow, Mira, Old Tobin and Pell say different things before and after you get your starter.

## Startup and game flow

```
Main
├── World (hidden and frozen until a game starts)
│   └── Player
├── UI (map banner, dialogue box)
└── TitleScreen
```

- **`GameSession`** (autoload) owns the flow between the title and gameplay. Menus only call its high-level actions: `continue_game()`, `start_new_game()` and `return_to_title()`, the last of which is reserved for a future pause menu.
- **Transitions** use SceneRouter's fade: the session's work happens while the screen is black.
- **Resetting:** both New Game and Continue first call the single reset path, `GameSession._reset_runtime_state()`. It calls `GameState.reset()` (flags back to `GameState.INITIAL_FLAGS`), clears the party and unloads the map, so nothing from a previous session can leak into the next one.
- **Afterwards:** New Game loads the starting map at its spawn point; Continue applies the save.
- **New story flags** get their starting value in `GameState.INITIAL_FLAGS`.

## Wild encounters

```
EncounterZone (tall grass) → EncounterManager → EncounterTable → species + level
  → CreatureFactory → wild CreatureInstance → encounter_started → BattleManager → … → end_encounter()
```

- **`EncounterZone`** (`scenes/encounters/encounter_zone.tscn`) is an `Area2D` that draws its own tall grass, so the visible grass always matches the encounter area.
  - Settings: `size_tiles`, `encounter_enabled`, `encounter_rate` (default 10% per step), `encounter_table`, `step_length` (16 px), and the grass and tuft textures.
  - It tracks the player with enter/exit signals and counts a "step" for every 16 px actually walked inside. Standing still, walking into a wall, being frozen by dialogue or menus, and teleports never count.
- **`EncounterManager`** (autoload) handles each step:
  - rolls the zone's rate using its `rng` (tests swap in a seeded generator);
  - picks a weighted entry from the table, then a level within its range;
  - creates the creature with `CreatureFactory`;
  - wraps it in a `WildEncounter` (creature, table, source map, source zone) and emits `encounter_started`.
- **Rules:**
  - No encounters during dialogue, transitions or another encounter.
  - After each encounter there are 3 grace steps before the next can happen.
  - Wild creatures never join the party and are never saved.
- **No encounters before a starter.** Wild creatures only appear once `starter_selected` is true and a party creature still has HP. You can walk through grass before that, or with a fainted team, without anything appearing.
- **`BattleManager`** listens for `encounter_started` and takes over from there (see Battles).

**Route 01's table** (`data/encounters/route_01.tres`, all Lv. 2–5): Flamkit 15, Aquaphin 15, Mossaur 15, Pebblit 15, Cindrake 10, Rivulet 10, Thornling 10, Brambleox 5, Tideclaw 5, for a total of 100. Each entry owns exactly `weight` of the possible rolls (`EncounterTable.entry_for_roll()`), which is how the tests prove every species is reachable without relying on statistics.

### Adding an encounter area (forest, cave, lake…)

1. Create an `EncounterTable` in `data/encounters/` and add `EncounterEntry` items: `species_id`, `min_level`, `max_level`, `weight`.
2. In the map scene, instance `encounter_zone.tscn` (under an `EncounterZones` node), set `size_tiles`, and assign the table.

No code changes are needed. To change how tall grass looks, replace `assets/tilesets/tall_grass.png` and `assets/sprites/objects/grass_tuft.png`, or set different textures on a zone.

## Battles

```
EncounterManager --encounter_started(WildEncounter)--> BattleManager (rules) --events--> BattleScene (presentation)
```

**Who does what**

- **`BattleManager`** (autoload) owns the rules. It holds the battle and its state, and resolves each turn into a list of `BattleEvent`s: move used, missed, damage, fainted, victory, EXP gained, level-up, defeat. It applies results immediately to the real party `CreatureInstance` and the encounter's temporary wild creature.
  - Signals: `battle_started`, `turn_resolved`, `battle_won`, `battle_lost`, `battle_finished` (`battle.outcome` is `victory`, `defeat`, `escaped` or `caught`).
  - It never waits for animations, and it calls `EncounterManager.end_encounter()` once the scene reports it's done.
- **`BattleScene`** only presents. It shows both creatures, collects input, plays the event list back with messages (`BattleMessages`) and animations, then asks `BattleManager` for the next step.

**States**

- `BattleManager`: `NONE → INTRO → PLAYER_ACTION ⇄ TURN_RESOLUTION → (SWITCH_REQUIRED → PLAYER_ACTION) → VICTORY | DEFEAT | ESCAPED | CAUGHT → NONE`.
- The scene's own UI states: `INTRO`, `ACTION_MENU`, `MOVE_MENU`, `CREATURE_MENU`, `ITEM_MENU`, `PLAYING`, `ENDING`.
- Menu browsing is presentation only, so it lives in the scene. Anything that changes the battle goes through `BattleManager`:

  | Action | Call |
  |---|---|
  | FIGHT | `submit_move()` |
  | CREATURE | `submit_switch()` |
  | ITEM | `submit_item()`; legality via `get_item_problem()` |
  | RUN | `submit_run()` |

  The wild creature's turn and the faint check happen inside `TURN_RESOLUTION`.
- **Fainting is not losing.** When the active creature faints and another can still fight, the battle enters `SWITCH_REQUIRED` (`battle.awaiting_switch`) and the player must choose a replacement. The menu can't be closed, and the replacement comes in for free. Defeat happens only when no party creature can fight.

**Actions**

| Action | Status | What it does |
|---|---|---|
| FIGHT | Implemented | Lists the creature's own moves with element and power. |
| RUN | Implemented | Wild battles only. Success ends the battle with no EXP and the wild creature untouched. Failure gives the wild creature a free turn. |
| CREATURE | Implemented | Lists the party straight from `PartyManager`: name, level, HP / max HP, status, an Active / Fainted tag, and "Empty" for free slots. Switching to a healthy reserve uses your turn ("Flamkit, come back!", "Go, Pebblit!", then the wild creature attacks). The active creature, fainted ones and empty slots can't be chosen; choosing one explains why. |
| ITEM | Implemented | Lists items with quantities ("Capture Orb x5"). With none left: "Out of Capture Orbs." Nothing is consumed and the turn isn't used. |

**The active creature** (the lead) is `PartyManager.get_active_index()` (default slot 0, saved). Choose it on the party screen; it also changes when you switch in battle. It's the creature that fights the next battle. If it can't fight when a battle starts, the first party creature that can takes over.

**Capturing**

- Using a Capture Orb consumes one, then rolls `BattleCalculator.capture_chance()`:
  - `clamp(0.65 × (1 − current HP / max HP), 2%, 95%)`, so full HP gives 2%, half HP 32.5% and 1 HP left about 64%;
  - a creature at 0 HP can't be caught.
- **Success** ("Pebblit was caught!"): the wild creature becomes a real owned `CreatureInstance` via `CreatureFactory.create_from_wild()`. It keeps its species, level, EXP, current HP, moves and status; gets a new UID; and its nickname starts as the species name. It joins the party ("joined your team!"), or goes to storage when the party has 6 ("Your party is full." / "was sent to storage."). The battle ends and gives no EXP.
- **Failure** ("Oh no! Pebblit broke free!"): the wild creature takes its turn and the battle continues.

**Storage.** `CreatureStorage`, owned by `GameSession`, has no size limit and is managed at the storage terminal (see Managing creatures). It is saved in the same creature format as the party.

**Items.** `ItemData` resources in `data/items/` only describe an item; `ItemCatalog` registers and validates them. The `Inventory` (owned by `GameSession`) holds id → quantity. New Game starts with 5 Capture Orbs.

**Rules** (placeholders, each kept in one place)

| Rule | Where | Details |
|---|---|---|
| Damage | `BattleCalculator` | `base = ((2 × level / 5 + 2) × power × attack / defense) / 50 + 2`, then `damage = floor(base × random(0.85–1.0) × element)`. Minimum 1 for any move with power. No critical hits yet. |
| Elements | `ElementData` (`strong_against` / `weak_against` lists) | Ember > Verdant > Tide > Ember at 2×, reversed at 0.5×. Neutral and same-element hits are 1×. |
| Turn order | `BattleCalculator` | Higher Speed acts first; ties are a coin flip from the battle RNG. |
| Escape | `BattleCalculator` | `clamp(0.75 × player speed / wild speed + 0.15 × failed attempts, 25%, 95%)`. Equal speed gives 75%. |
| Capture | `BattleCalculator` | `clamp(0.65 × (1 − HP / max HP), 2%, 95%)`; 0 at 0 HP. |
| Matchup labels and messages | `BattleCalculator.element_multiplier()` | The move menu's Effective / Normal / Not very effective label comes from `BattleManager.preview_effectiveness()`. The "Super effective!" / "Not very effective..." lines come from the multiplier stored on the damage event. The UI never works out matchups itself. |
| Accuracy | `MoveData.accuracy` | Percent. All current moves are 100. |
| Wild AI | `BattleAI` | A random move the creature actually knows and that exists. |
| EXP | `CreatureProgression` | Reward `max(1, wild level × 10)`. Level L → L+1 needs `L × L × 10`. `experience` is progress within the current level. |
| Level-up | `CreatureProgression` | Stats are derived from level. Current HP rises by however much max HP grew. Level cap 100. |

**How a battle ends**

- **Victory:** messages, then EXP and any level-ups, then back to the world.
- **Capture:** the caught creature joins the party or storage, then you're back in the world. No EXP.
- **Defeat (no usable creature):** "Flamkit fainted!" and "Your team has no other available creatures." The creature stays in the party at 0 HP and you return to the world. Encounters stay off until the party is healed.
- **Healing:** rest in your bed at home and answer YES. It heals every owned creature, party and storage. The bed is a `HealPoint`, a reusable component on the shared `Interactable`.
- **Returning to the world:** the map stays loaded underneath the battle, so you're back at exactly the same spot and facing.

**Saving.** A battle is autosaved only after it has fully finished (EXP and level-ups applied, battle closed, back in the world), never mid-battle. Wild creatures are never saved.

**Test and debug hooks.** `BattleManager.rng` can be seeded, and these overrides exist on `BattleManager` (reset with `reset_test_overrides()`):

| Override | Effect |
|---|---|
| `force_hit` | Every move hits. |
| `forced_random_factor` | Fixed damage roll. |
| `forced_damage` | Exact damage for every hit. |
| `forced_ai_move` | Wild creature always uses this move. |
| `forced_turn_order` | Fixed turn order. |
| `forced_escape` | Running always succeeds or always fails. |
| `forced_capture` | Capture always succeeds or always fails. |

Normal play never sets them.

## Assets

See [ASSET_LICENSES.md](ASSET_LICENSES.md). Never use Pokémon or other copyrighted game assets.
