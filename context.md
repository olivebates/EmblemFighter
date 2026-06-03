NEVER USE := TO DECLARE OR CHANGE VARIABLES, ONLY USE =
# EmblemFighter — Context Document

## Project Overview

A Fire Emblem-style tactical battle game built in Godot 4 (GDScript).  
Up to **4 heroes** fight enemies across a sequence of designed rooms on a variable-size grid (**32×32 px tiles**; rows 0–1 reserved for HUD). The player controls heroes on their turn; enemies use AI on their turn. Combat uses a weapon-triangle damage system. Clearing all enemies ends the wave — a **Victory Menu** slides in, the player edits their team loadout and forges/upgrades items, then starts the next round in the next room.

**Display:** 960×540 viewport, stretch mode `viewport` with integer scaling.

A Godot executable (`Godot_v4.5.1-stable_win64.exe`) lives in the project root and can be used to test builds directly from `cd <project> && ./Godot_v4.5.1-stable_win64.exe --headless --editor --path . --quit` for parse checks.

---

## File Structure

```
EmblemFighter/
├── project.godot
├── Godot_v4.5.1-stable_win64.exe
├── battle/
│   ├── Battle.tscn / Battle.gd
│   ├── BattleManager.gd
│   ├── Grid.gd
│   └── units/  Unit.gd / HeroUnit.gd / EnemyUnit.gd
├── ui/
│   ├── BattleHUD.tscn / BattleHUD.gd
│   └── VictoryMenu.gd              # built entirely in code, no .tscn
├── autoloads/
│   ├── Utils.gd
│   ├── UITheme.gd
│   ├── Combat.gd
│   ├── Heroes.gd / Enemies.gd / Skills.gd / Passives.gd / Equipment.gd
│   ├── RoomLibrary.gd          # sequential room loading, active_room / active_room_packed
│   ├── BuffDebuff.gd           # status effect definitions + skill assignment
│   └── PlayerInventory.gd
├── resources/
│   ├── HeroData.gd / EnemyData.gd / SkillData.gd / PassiveData.gd
│   ├── EquipmentData.gd / EnemySpawnConfig.gd
│   ├── RoomData.gd             # runtime room state (terrain, spawns, background)
│   ├── StatusEffectData.gd     # buff/debuff data class
│   ├── WeaponTriangle.gd
│   └── Grade.gd
├── battle/
│   └── rooms/
│       ├── RoomScene.gd        # @tool Node2D — base script for all room .tscn files
│       ├── GridBounds.gd       # @tool — white rect node that sets grid W×H
│       ├── SpawnZone.gd        # @tool — coloured rect node for hero/enemy spawn areas
│       ├── Room1.tscn … RoomN.tscn
│       └── tilesets/           # floor / wall / cover TileSet resources
├── data/
│   ├── heroes/    hero_01–06.tres
│   ├── enemies/   enemy_01–06.tres
│   ├── skills/    skill_01–06.tres
│   ├── passives/  passive_01–06.tres
│   └── equipment/ equip_01–06.tres
└── Sprite/Placeholders/
    ├── heroes.png   (224×224, 32×32 frames)
    ├── monsters.png (384×416)
    ├── Skills.png   (352×832, col 0 used for all item icons)
    ├── tile_grass.png / tile_mountain.png / tile_forrest.png  (32×32 tile sprites)
```

---

## Autoloads (Singletons)

Autoload registration order matters — **PlayerInventory must be last**.

### `autoloads/Utils.gd`
| Function | Description |
|---|---|
| `manhattan(a, b) -> int` | Manhattan distance. |
| `sprite_frame / random_left_column_frame / unique_left_column_frames` | Atlas frame extraction. |
| `floating_text(text, color, world_pos, parent, font_size=14)` | Label drifts upward and fades. |
| `launch_projectile(from, to, color, parent) -> Signal` | 8×8 tween projectile. |
| `damage_tier / shake_node / shake_for_hit / hitstop / hitstop_duration / show_damage_text` | Combat juice. |

### `autoloads/UITheme.gd`
Shared colors, font sizes, `StyleBoxFlat` helpers. `panel_style(bg, border, radius, width)` creates styled boxes. `apply_button_theme(btn, active, radius)` sets all button states.

Key color constants: `PANEL_BG_DARK`, `PANEL_BG`, `BTN_BG`, `BTN_BG_HOVER`, `BTN_BORDER`, `BTN_BORDER_HOVER`, `HERO_ACCENT`, `ENEMY_ACCENT`, `TEXT_PRIMARY`, `TEXT_SUBTLE`, `TEXT_MUTED`, `COLOR_HEAL`, `COLOR_DAMAGE_NORMAL`, `COLOR_DAMAGE_KILL`.

Badge/chip helpers: `badge_panel_style(tint)`, `badge_header_style(tint, header)`, `chip_style(color)`.

### `autoloads/Combat.gd`
All combat logic. Signals: `skill_executed`, `unit_died`, `damage_dealt`, `passive_triggered`.
- Skill damage/heal uses `skill.eff_damage()` (grade-scaled).
- Passive effects use `passive.eff_value()` (grade-scaled).
- `armor_pierce` subtracts from target DEF; `damage_reduction` applied post-calc.
- All 4 passive slots active simultaneously; trigger functions iterate `unit.get_passives()`.

### `autoloads/Equipment.gd`
Loads `.tres` pool. `apply_bonuses(unit, equip)` uses `equip.eff_atk()`, `eff_def()`, `eff_hp()`, `eff_block_pct()`. No speed items. `block_pct` stacked per hero, capped at 30%.

### `autoloads/BuffDebuff.gd`
Defines 3 buffs and 3 debuffs as `StatusEffectData` instances. Assigns them randomly (seeded RNG 1337, 0–2 effects per skill) to all `Skills.pool` entries at startup using the skill resource as the dictionary key.

| Effect | Type | Description |
|---|---|---|
| ATK UP | Buff | +5 ATK for 2 turns |
| REGEN | Buff | +8 HP/turn for 3 turns |
| SHIELD | Buff | −20% damage taken for 2 turns |
| ATK DOWN | Debuff | −5 ATK for 2 turns |
| POISON | Debuff | 6 damage/turn for 3 turns |
| SLOW | Debuff | −2 movement for 2 turns |

Key method: `get_effects_for_skill(skill: SkillData) -> Array` returns assigned `StatusEffectData` list.

### `autoloads/PlayerInventory.gd`
**Source of truth for all player-owned data.**

**State variables**

| Variable | Description |
|---|---|
| `owned_heroes` | 3 random heroes chosen at start |
| `deployed_ids: Array[StringName]` | Up to 4 slots; `&""` = empty |
| `slot_skills_map / slot_passive_map / slot_equipment_map` | slot_idx → Array[T] size 4 (slot-based) |
| `item_pool_skills / passives / equipment` | Unequipped items |
| `item_icons: Dictionary` | Resource → Texture2D; unique icons, assigned once at init |
| `hero_hp / hero_ko / hero_mana` | Persisted per-hero state |
| `gear_tokens / skill_tokens / passive_tokens` | Upgrade tokens; earned only by dismantling |

**Key methods**

| Method | Description |
|---|---|
| `sync_to_heroes()` | Copies slot items to `Heroes.*` dicts for deployed heroes. |
| `equip_*/unequip_*(slot, item_slot, item)` | Pool ↔ slot management. |
| `move_item_to_slot(dest_deploy, mode, dest_item_slot, item)` | Move from wherever to new slot. |
| `save_battle_state(hero_units)` | Saves HP, KO, mana before victory pause. |
| `can_start_round() -> bool` | True if ≥1 deployed hero alive. |
| `upgrade_item(mode, item) -> bool` | Costs `grade³` tokens; no cap. |
| `dismantle_item(mode, item) -> bool` | Unequipped only; yields `((grade-1)×grade/2)²` tokens. |
| `dismantle_all_unequipped(mode) -> int` | Dismantles entire pool; returns count. |
| `get_tokens(mode) -> int` | Token count for `"equipment"/"skill"/"passive"`. |
| `find_item_location(mode, item) -> Dictionary` | `{deploy_slot, item_slot}` or `{}`. |
| `get_all_equipped_items(mode) -> Array` | All non-null equipped items across all slots. |

**Initialization:** 3 random heroes → items distributed → `_assign_all_icons()` → `_add_test_grade_items()` (grades 1–21, one duplicate per type) → `sync_to_heroes()`.

---

## Grade System (`resources/Grade.gd`)

Static helper (`class_name Grade extends RefCounted`). No autoload. All functions are `static`.

**Ladder:** 1 Junk, 2 Crude, 3 Standard, 4 Improved, 5 Superior, 6 Elite, 7 Flawless, 8 Supreme, 9 Masterwork, 10 Divine, 11 Mythical, 12 Cosmic, 13 Immortal, 14 Omniscient, 15 God-like, 16–18 Void/Void+2/Void+3, 19 Infinite. Grades above 19 → `"Infinite +N"`.

| Function | Returns |
|---|---|
| `name_for(grade) -> String` | Grade name or `"Infinite +N"` |
| `outline_color(grade) -> Color` | Per-tier border colour |
| `bg_color(grade) -> Color` | `outline × 0.3` (70% darker) |
| `is_animated(grade) -> bool` | `grade >= 10` |
| `upgrade_cost(grade) -> int` | `grade³` |
| `dismantle_yield(grade) -> int` | `((grade-1) × grade / 2)²` — equals total tokens invested |
| `stat_mult(grade) -> int` | `grade²` |

---

## Data Classes

### `resources/StatusEffectData.gd`
`class_name StatusEffectData extends Resource`

| Field | Type | Description |
|---|---|---|
| `id` | StringName | Unique identifier |
| `display_name` | String | Short label shown in chips |
| `description` | String | Longer explanation shown on Alt |
| `duration` | int | Turns active |
| `is_debuff` | bool | false = buff (self), true = debuff (enemy) |
| `effect_type` | EffectType enum | ATK_UP / REGEN / SHIELD / ATK_DOWN / POISON / SLOW |
| `effect_value` | float | Magnitude |
| `color` | Color | Used for chip and display tinting |

### `resources/EquipmentData.gd`
`atk_bonus, def_bonus, hp_bonus, block_pct` (no speed), `grade: int = 1`.
- `eff_atk() / eff_def() / eff_hp()` = bonus × `grade²`
- `eff_block_pct()` = `grade × 1%` if `block_pct > 0`, else 0. Hero total capped at 30%.

### `resources/SkillData.gd`
`base_damage, range, mana_cost, attack_type_override, target_type, aoe_radius`, `grade: int = 1`.
- `eff_damage()` = `base_damage × grade²` (sign preserved for heals)
- `attack_type_override: WeaponTriangle.Type` — MELEE / RANGE / MAGE

### `resources/PassiveData.gd`
`trigger_event, effect_type, effect_value`, `grade: int = 1`.
- `eff_value()` = `effect_value × grade²`

### `resources/HeroData.gd`
`base_hp/atk/def/spd`, OP buff fields: `op_buff_name/description/type/value`.

| Hero | Buff |
|---|---|
| Aldric | Fortress — DEF +15 |
| Bryn | Berserker — ATK +12 |
| Sera | Deadeye — Always crits |
| Lyris | Armor Break — Ignore 5 DEF |
| Kael | Iron Aura — 35% damage reduction |
| Mirelle | Ancient Blood — HP +50 |

---

## Room System

### `autoloads/RoomLibrary.gd`
- Scans `battle/rooms/*.tscn` at startup, sorted alphabetically (Room1 → Room2 → …).
- `current_room_index` tracks position in sequence; wraps around.
- `pick_next_room()` advances index and calls `_apply_room()` — called by `BattleManager.start_next_round()`.
- `active_room: RoomData` — extracted game data (terrain, spawns, background texture).
- `active_room_packed: PackedScene` — the raw scene, instantiated by Grid for TileMapLayer rendering.

### Room scenes (`battle/rooms/Room*.tscn`)
Each room scene extends `RoomScene.gd` (`@tool Node2D`) with these child nodes:

| Node | Class | Purpose |
|---|---|---|
| `GridBounds` | `GridBounds` | White rect — sets `grid_cols` / `grid_rows` (locked to origin) |
| `FloorLayer` | TileMapLayer | Visual floor tiles (floor_tileset.tres — tile_grass.png) |
| `WallLayer` | TileMapLayer | Impassable terrain (wall_tileset.tres — tile_mountain.png) |
| `CoverLayer` | TileMapLayer | +3 DEF cover (cover_tileset.tres — tile_forrest.png) |
| `HeroSpawn` | `SpawnZone` | Blue rect — drag to set hero placement zone |
| `EnemySpawn` | `SpawnZone` | Red rect — drag to set enemy spawn zone |

**Inspector exports on root node:**
- `background_texture: Texture2D` — tiled 10 tiles outside the grid in all directions (z_index −10).
- `enemy_spawns: Array[EnemySpawnConfig]` — list of `{enemy: EnemyData, count: int}` entries. Empty = random escalation fallback.

`GridBounds` and `SpawnZone` are hidden at runtime (visible only in editor). The room scene itself is instantiated as a child of Grid (z_index −5) so its TileMapLayers render in-game above the background and below grid lines.

### `battle/Grid.gd`
- Variable `GRID_W` / `GRID_H` loaded from `RoomLibrary.active_room`.
- In `_load_room_data()`: populates `terrain` dict from RoomData walls/covers, then instantiates `active_room_packed` as a child Node2D (z_index −5) for TileMapLayer rendering.
- Background Sprite2D (z_index −10) created from `room.background_texture`.
- Grid lines Node2D at z_index −2.
- `reload_room()` frees the old room instance and background, then re-runs the above.
- Draw order within Grid: background (−10) → room TileMapLayers (−5) → grid lines (−2) → everything else (0).

## Battle System

### `battle/BattleManager.gd`
Core turn controller. Key signal: `victory_achieved` (tree paused before emit).
- **PLACEMENT state** (new): heroes are placed at battle start; player can click to reposition within the hero spawn zone. "Start Combat" button triggers `_begin_round()`.
- `seed(RoomLibrary.current_room_index)` called before `_spawn_units()` — deterministic hero/enemy placement per level.
- Enemy spawning: uses `RoomData.enemy_spawns` (configured per room) if non-empty; otherwise falls back to random escalation (`max(2, _enemy_wave_size)`).
- `start_next_round()` calls `RoomLibrary.pick_next_room()` then `grid.reload_room()`.
- `_game_over(true)`: saves state to `PlayerInventory`, pauses tree, emits `victory_achieved`.
- Every 3 initiative cycles: all living enemies gain +1 ATK.

### `battle/units/Unit.gd`
Base class for all units. Key fields: `grid_pos`, `hp`, `max_hp`, `attack_type: WeaponTriangle.Type`, `bonus_atk/def/spd`, `crit_chance`.

- `_draw()` renders a 2×2 colored type dot with 1px black outline at the bottom-left of the sprite (local coords −15,11). Colors: MELEE=red, RANGE=green, MAGE=blue. `queue_redraw()` called at end of `init_stats`.
- Standard animations: `play_attack_windup`, `play_attack_animation`, `play_hit_animation`, `play_crit_hit_animation`, `play_heal_animation`, `play_death_animation`, `play_knocked_out_animation`.

### `battle/units/HeroUnit.gd`
Extra state: `skills, passives, equipments, skill_icons, used_skills, movement_remaining, armor_pierce, damage_reduction, mana (max 10)`.

`setup(data)` applies stats, sprite, all equipment bonuses, then `_apply_op_buff(data)`.

---

## UI

### `ui/VictoryMenu.gd`
`CanvasLayer` (layer 10, `PROCESS_MODE_ALWAYS`), built entirely in code. No title label.

**Key instance variables:**
- `_forge_cards: Dictionary` — item Resource → PanelContainer (for targeted updates)
- `_forge_grid: GridContainer` — stored for `move_child` re-sorting
- `_root_ctrl: Control` — full-screen root; token-dot particles added here
- `_displayed_tokens: int` — animated counter value (increments as dots arrive)
- `_undo_item / _undo_mode / _undo_yield / _undo_icon` — undo state for last dismantle

---

### Tab 1 — Team
4 slot cards → hero picker popup (5-col icon grid; KO'd grayed/disabled; deployed have green border).

---

### Tab 2 — Loadout
4 slot selector → 3 columns (Gear / Skills / Passives), each a 2×2 grid of 56×56 icon slots with grade-colored borders.

**Item picker popup:**
- Sort order: current slot item first → equipped-in-other-slots (grade desc) → pool items (grade desc)
- Equipped items (elsewhere): transparent background (`Color(0,0,0,0)`), grade-colored border; on hover faint grade tint
- Pool items: grade-colored style via `_apply_grade_style`
- Clicking outside closes

---

### Tab 3 — Forge

**Grid:** 6 columns, `custom_minimum_size = Vector2(0, 135)`, `SIZE_EXPAND_FILL` horizontal → uniform cards.

**Card layout (top to bottom):**
- `content_vb` (VBoxContainer, `SIZE_EXPAND_FILL`, `ALIGNMENT_CENTER`):
  - `icon_rect` (TextureRect, `SIZE_EXPAND_FILL` both axes, `STRETCH_KEEP_ASPECT_CENTERED`) — resizes to fill
  - `name_lbl` (13pt, centered)
  - `grade_lbl` (10pt, grade-colored, centered) — animated for grade ≥ 10
- 14px separation
- `btn_row` (HBoxContainer, pinned to bottom): `+` and `x` (or "Equipped" label)

**Satisfaction effects:**
- **Upgrade**: card punch + border flash white→grade color; tier-crossing floating text (e.g. "✦ Divine") at card center; screen shake 4px; undo state cleared
- **Dismantle**: `"+N"` floating text at card center; N token dots fly in cubic-bezier arcs (random burst direction → home to wallet) at double speed (0.7–1.1s); remaining cards slide into gap; screen shake 3px; undo state set
- **Token dots**: each dot increments `_displayed_tokens` on arrival, punches the token label

**Bottom bar (left → right):**
- **Undo button**: shows last dismantled item's icon; clicking restores item; cleared on upgrade
- **Token label** (centered): "Gear Tokens: ⚙ N" format; only shows on Forge tab
- **Dismantle All Unequipped**: 3-press confirm; hover tip shows summed yield
- **Next Round**

---

### `ui/BattleHUD.gd`

`CanvasLayer` managing all in-battle UI overlays. Key sub-systems:

#### Highlight system
- **Move range**: colored fill tiles + 2px black perimeter outline (`_move_highlights`, `_move_outline`)
- **Skill range**: colored fill tiles + 2px colored perimeter outline by attack type (`_skill_range_highlights`, `_skill_outline`)
  - MELEE = red, RANGE = green, MAGE = blue
- **Valid targets**: yellow outline per tile (`_valid_target_highlights`)
- **Kill overlays**: red fill on tiles where attack would kill (`_kill_highlights`)
- **AoE cursor**: tinted fill under cursor for AoE skills
- **Move ghosts**: fade-out fill at unit's previous position
- **Unit glows**: outline + faint fill on reachable targets

`set_highlight_mode(mode)` clears the appropriate stores when the mode changes.

#### Skill badge ("Will Use" / "ACTIVE" popup)
Floating `PanelContainer` anchored near the active skill's targets. Created by `_create_skill_badge`.

**Badge layout (top to bottom inside `col` VBoxContainer):**
- Header strip (only for non-"WILL USE" headers): `ACTIVE` label with tint background
- Separator
- `IdentityRow` HBoxContainer: `[SkillIcon 30×30] [VBox: SkillName / AttackTypeLabel]`
  - AttackTypeLabel shows "Melee", "Ranged", "Mage", "Heal", "Self Buff", or "Support"
- `DamageSeparator` (hidden when no previews)
- `DamageBreakdown` VBoxContainer (hidden when no previews):
  - `TargetRows` VBoxContainer — one row per target:
    - `NameDmgRow` HBoxContainer: `[TargetName EXPAND] [DamageValue SHRINK_END]`
      - Multi-target: name visible, damage small (11pt) with "−X" format
      - Single-target: name hidden, damage large (22pt) centered with "X DMG" format
    - `ModRow` HBoxContainer — modifier chips (Base DMG, ADV/WEAK, −DEF, −Cover); **Alt-only**
    - `KillLabel` — "☠ KILL" at 16pt, always visible when `is_kill`
  - `TotalRow` HBoxContainer — "TOTAL X DMG" shown only for multi-target
    - Color: green if total ≥ sum(base_power), red if below
  - Single-target `DamageValue` color: green if dmg ≥ base_power, red if below
- `DetailHint` label ("Hold Alt for breakdown") — always visible
- `BadgeCaret` (▼)

**Badge positioning** (`_position_badge_for_targets`):
- Reads `target_positions` meta (set from previews) and `hero_grid` meta (caster position)
- Considers both hero AND target positions for rightmost/leftmost x
- Places badge to the right of the rightmost entity; falls back to left if off-screen
- Vertically centered at midpoint between hero and average target y; clamped to screen

**Badge metadata stored:** `skill`, `badge_tint`, `target_positions`, `hero_grid`, `badge_fallback_grid`, `skill_index`

#### Status effects description panel (`_effects_desc_panel`)
Separate `PanelContainer` to the right of the main badge. Created by `_create_effects_desc_panel` when a skill with assigned effects is active.

- Shows per-effect: `[chip + duration]` row, then "Self"/"Enemy" target indicator (always visible), then description text (Alt-only, node name `"EffectDetail"`)
- X position: always right of badge's `get_combined_minimum_size().x`; recalculated every frame and on Alt toggle
- Y position: matches badge's `position.y` (same top edge), clamped to screen
- Uses same `badge_panel_style(tint)` as the main badge (matching border color)

#### Alt key (`_detail_chips_visible`)
Toggled in `_process` by `Input.is_key_pressed(KEY_ALT)`. When it changes, `_refresh_badge_chip_visibility` runs:
- Toggles all `"EffectDetail"` named nodes in desc panel (description text only)
- Shows/hides `_weakness_panel`
- Shows/hides all `ModChip` nodes in `ModRow`s
- Calls `_relayout_effects_panel()` to update desc panel x

#### Weakness panel (`_weakness_panel`)
Small panel at screen position `(8, 44)`, shown only when Alt held. Title "Damage Advantages". Three rows: `[Mage] > [Melee]`, `[Melee] > [Range]`, `[Range] > [Mage]` using colored chips.

#### Active actor ring
Animated corner-bracket ring (`_active_actor_ring`) around the currently acting unit. Tracks unit's grid_pos every frame. Created in `set_active_actor`, freed in `clear_active_actor`.

#### Other HUD elements
- **Turn order bar**: top chrome; up to 8 unit portrait slots with timeline line
- **Skill bar**: bottom HBoxContainer; "End" button + one slot per hero skill; active skill pulses
- **Radial menu**: floating buttons around hero's screen position (legacy, partially superseded by skill bar)
- **Enemy telegraph**: highlights enemy's intended move destination and target
- **Counter highlights**: edge outline on heroes that can counter-attack
- **Hover outline**: white 2px outline on interactable hovered tile
- **Damage preview label**: small text label showing preview info (bottom-left area)

---

### Tooltips
Mouse-following `PanelContainer`, fades in 0.07s.

**Item tooltip structure (skill / passive / equipment):**
1. Header: name + [type] for skills; name for others; icon thumbnail
2. **Grade subtitle** (10pt): grade name in grade color; if equipped appends `"  —  Equipped"` in `TEXT_MUTED`
3. Separator
4. Stats (all grade-scaled via `eff_*` functions)
5. Description (9pt, muted)

**Hero tooltip:** portrait + name → Health · Damage · Block · Mana → Hero Traits (OP buff).

---

## Features

### Item Grade System
- All items start at **grade 1 (Junk)**; no maximum grade
- **Upgrade cost:** `grade³` tokens of item's type
- **Dismantle yield:** `((grade-1) × grade / 2)²` = total tokens ever invested in the item (100% refund)
- **Stat scaling:** `grade²` for flat bonuses; block% linear `grade × 1%`, capped 30%/hero
- Three token pools: `gear/skill/passive_tokens`; earned only by dismantling
- Test items: one duplicate per grade 1–21 added to each pool at startup
- Undo: last-dismantled item stored in `_undo_item`; upgrade clears it to prevent negative-balance exploit

### Round Structure
- Clear enemies → 0.5s → `save_battle_state()` → tree paused → VictoryMenu slides in
- Edit team/loadout/forge → Next Round → `start_next_round()` → +1 enemy

### Slot-Based Loadout
- Items tied to deployment slots (0–3), not heroes; swapping hero leaves items in place
- `sync_to_heroes()` copies slot items to whichever hero is deployed in that slot

### Weapon Triangle
- Heroes only, per-skill `attack_type_override`; enemies use flat ×1.0
- MAGE > MELEE > RANGE > MAGE; advantage ×2.0, disadvantage ×0.5
- Type color coding: **red = Melee, green = Range, blue = Mage**
  - Used for: skill range outline, unit type dot (bottom-left of sprite), weakness panel chips

### Status Effects (`BuffDebuff` autoload)
- Randomly assigned to skills (seeded, 0–2 effects per skill)
- Display-only in current implementation (not applied to gameplay stats yet)
- Buffs applied to self, debuffs applied to enemy target
- Shown in main badge (chip list in EffectsRow — removed; now only in desc panel)
- **Desc panel** shows: chip + duration, "Self"/"Enemy" (always), description text (Alt-only)

### Mana
- 10 max, persists between rounds, regenerates +1/round; skills have `mana_cost`

### Passives / Equipment
- All 4 slots of each active simultaneously
- Equipment block stacks across slots, capped at 30% per hero

### Win / Loss
- Wave cleared → victory menu
- No deployed living heroes → Next Round disabled (soft lose; no screen)
- Cycle escalation: every 3 initiative cycles, all living enemies gain +1 ATK
