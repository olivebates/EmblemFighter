NEVER USE := TO DECLARE OR CHANGE VARIABLES, ONLY USE =
# EmblemFighter — Context Document

## Project Overview

A Fire Emblem-style tactical battle game built in Godot 4 (GDScript).  
Up to **4 heroes** fight escalating enemy waves on a **16×14 playable** grid (**32×32 px tiles**; rows 0–1 reserved for HUD). The player controls heroes on their turn; enemies use AI on their turn. Combat uses a weapon-triangle damage system. Clearing all enemies ends the wave — a **Victory Menu** slides in, the player edits their team loadout and forges/upgrades items, then starts the next round with one more enemy.

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
│   └── PlayerInventory.gd
├── resources/
│   ├── HeroData.gd / EnemyData.gd / SkillData.gd / PassiveData.gd
│   ├── EquipmentData.gd
│   ├── WeaponTriangle.gd
│   └── Grade.gd
├── data/
│   ├── heroes/    hero_01–06.tres
│   ├── enemies/   enemy_01–06.tres
│   ├── skills/    skill_01–06.tres
│   ├── passives/  passive_01–06.tres
│   └── equipment/ equip_01–06.tres
└── Sprite/Placeholders/
    ├── heroes.png   (224×224, 32×32 frames)
    ├── monsters.png (384×416)
    └── Skills.png   (352×832, col 0 used for all item icons)
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

Key color constants: `PANEL_BG_DARK`, `PANEL_BG`, `BTN_BG`, `BTN_BG_HOVER`, `BTN_BORDER`, `BTN_BORDER_HOVER`, `HERO_ACCENT`, `ENEMY_ACCENT`, `TEXT_PRIMARY`, `TEXT_SUBTLE`, `TEXT_MUTED`, `COLOR_HEAL`, `COLOR_DAMAGE_NORMAL`.

### `autoloads/Combat.gd`
All combat logic. Signals: `skill_executed`, `unit_died`, `damage_dealt`, `passive_triggered`.
- Skill damage/heal uses `skill.eff_damage()` (grade-scaled).
- Passive effects use `passive.eff_value()` (grade-scaled).
- `armor_pierce` subtracts from target DEF; `damage_reduction` applied post-calc.
- All 4 passive slots active simultaneously; trigger functions iterate `unit.get_passives()`.

### `autoloads/Equipment.gd`
Loads `.tres` pool. `apply_bonuses(unit, equip)` uses `equip.eff_atk()`, `eff_def()`, `eff_hp()`, `eff_block_pct()`. No speed items. `block_pct` stacked per hero, capped at 30%.

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

**Animation tiers** (`_animate_card_full` in VictoryMenu): 3 independent layers — border fastest (×1.0), grade label medium (×1.18), background slowest (×1.42). Each starts at a random phase via a one-shot warmup tween → clean looping tween. **Infinite+ (19+)** is the exception: all three layers synchronized, start at hue 0, step 2.0s.

Tier animation colors (two-color pulse):
- Divine (10): orange ↔ deep amber
- Mythical (11): gold ↔ amber
- Cosmic (12): purple-blue ↔ indigo
- Immortal (13): pink ↔ magenta
- Omniscient (14): cyan ↔ teal
- God-like (15): white-hot ↔ gold
- Void (16–18): bright purple ↔ deep indigo
- Infinite+ (19+): synchronized rainbow

---

## Data Classes

### `resources/EquipmentData.gd`
`atk_bonus, def_bonus, hp_bonus, block_pct` (no speed), `grade: int = 1`.
- `eff_atk() / eff_def() / eff_hp()` = bonus × `grade²`
- `eff_block_pct()` = `grade × 1%` if `block_pct > 0`, else 0. Hero total capped at 30%.

### `resources/SkillData.gd`
`base_damage, range, mana_cost, attack_type_override, target_type, aoe_radius`, `grade: int = 1`.
- `eff_damage()` = `base_damage × grade²` (sign preserved for heals)

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

## Battle System

### `battle/BattleManager.gd`
Core turn controller. Key signal: `victory_achieved` (tree paused before emit).
- `_enemy_wave_size`: incremented before each new wave in `start_next_round()`
- `_game_over(true)`: saves state to `PlayerInventory`, pauses tree, emits `victory_achieved`
- Enemy count = `max(2, _enemy_wave_size)`; spawn in top half of grid
- Every 3 initiative cycles: all living enemies gain +1 ATK

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

**Card styling:**
- Card border/bg: grade-colored (bg = outline × 0.3); equipped items have bg alpha 0.25
- Animated cards (grade ≥ 10): card's `StyleBoxFlat` animated directly; tweens stored in `tween_list` metadata
- `+` button: gray (0.45) if unaffordable, green (0.55, 1.0, 0.60) if equipped+affordable, white otherwise
- Grid sorted: equipped first (grade desc), then pool (grade desc)
- Clicking `+` when unaffordable: `Utils.floating_text("Not enough tokens", ...)`

**Satisfaction effects:**
- **Upgrade**: card punch + border flash white→grade color; tier-crossing floating text (e.g. "✦ Divine") at card center; screen shake 4px; undo state cleared
- **Dismantle**: `"+N"` floating text at card center; N token dots fly in cubic-bezier arcs (random burst direction → home to wallet) at double speed (0.7–1.1s); remaining cards slide into gap; screen shake 3px; undo state set
- **Dismantle All**: dots from each card, screen shake 6px; pool cards removed without full rebuild
- **Token dots**: each dot increments `_displayed_tokens` on arrival, punches the token label; dots use cubic bezier P0=source, P1=source+random burst, P2=target+approach, P3=target
- **Grid slide** (`_animate_cards_from`): records `global_position` before change, awaits one frame, tweens each moved card from old visual position to new (cubic ease, 0.28s)
- **`_resort_forge_cards`**: async; records positions → `move_child` sort → `_animate_cards_from`

**Bottom bar (left → right):**
- **Undo button** (Junk styling — dark gray bg, gray border): shows `↩` when empty; shows last dismantled item's icon when pending; hover tip shows "Undo dismantle (refunds N tokens)"; clicking restores item to pool and deducts tokens; cleared on upgrade or new dismantle
- **Token label** (centered in expanding spacer): "Gear Tokens: ⚙ N" format; only shows on Forge tab; updates live as dots land
- **Dismantle All Unequipped**: 3-press confirm ("Are you sure?" → "Are you really really sure?" → fires); hover tip shows summed yield; 18px horizontal padding
- **Next Round**
All bottom-bar forge controls hidden when not on Forge tab.

---

### Tooltips
Mouse-following `PanelContainer`, fades in 0.07s.

**Item tooltip structure (skill / passive / equipment):**
1. Header: name + [type] for skills; name for others; icon thumbnail
2. **Grade subtitle** (10pt): grade name in grade color; if equipped appends `"  —  Equipped"` in `TEXT_MUTED`
3. Separator
4. Stats (all grade-scaled via `eff_*` functions)
5. Description (9pt, muted)

Grade subtitle determined by `find_item_location(mode, item)` where mode is inferred from item type.

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

### Mana
- 10 max, persists between rounds, regenerates +1/round; skills have `mana_cost`

### Passives / Equipment
- All 4 slots of each active simultaneously
- Equipment block stacks across slots, capped at 30% per hero

### Win / Loss
- Wave cleared → victory menu
- No deployed living heroes → Next Round disabled (soft lose; no screen)
- Cycle escalation: every 3 initiative cycles, all living enemies gain +1 ATK
