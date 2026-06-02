NEVER USE := TO DECLARE OR CHANGE VARIABLES, ONLY USE =
# EmblemFighter — Context Document

## Project Overview

A Fire Emblem-style tactical battle game built in Godot 4 (GDScript).  
Two heroes fight escalating enemy waves on a **16×14 playable** grid (**32×32 px tiles**; rows 0–1 reserved for HUD). The player controls heroes on their turn; enemies use AI on their turn. Combat uses a weapon-triangle damage system. Clearing a wave of enemies triggers reinforcements (`wave_size + 1` new spawns).

**Display:** 960×540 viewport, stretch mode `viewport` with integer scaling.

---

## File Structure

```
EmblemFighter/
├── project.godot                # Entry point → Battle.tscn
├── battle/
│   ├── Battle.tscn              # Root battle scene (Battle + Grid + UnitsLayer + BattleManager + BattleHUD)
│   ├── Battle.gd
│   ├── BattleManager.gd
│   ├── Grid.gd
│   └── units/
│       ├── Unit.tscn
│       ├── Unit.gd
│       ├── HeroUnit.gd
│       └── EnemyUnit.gd
├── ui/
│   ├── BattleHUD.tscn
│   └── BattleHUD.gd
├── autoloads/
│   ├── Utils.gd
│   ├── UITheme.gd
│   ├── Combat.gd
│   ├── Heroes.gd
│   ├── Enemies.gd
│   ├── Skills.gd
│   ├── Passives.gd
│   └── Equipment.gd
├── resources/                   # Data class definitions
│   ├── HeroData.gd
│   ├── EnemyData.gd
│   ├── SkillData.gd
│   ├── PassiveData.gd
│   ├── EquipmentData.gd
│   └── WeaponTriangle.gd
├── data/                        # .tres resource files (stats only — no per-unit sprites)
│   ├── heroes/    (hero_01–06.tres)
│   ├── enemies/   (enemy_01–06.tres)
│   ├── skills/    (skill_01–06.tres)
│   ├── passives/  (passive_01–06.tres)
│   └── equipment/ (equip_01–06.tres)
└── Sprite/
    ├── Placeholders/
    │   ├── heroes.png           # Hero sprite sheet (224×224, 32×32 frames)
    │   ├── monsters.png         # Enemy sprite sheet (384×416)
    │   ├── Skills.png           # Skill icon sheet (352×832)
    │   └── placeholder.md       # Sheet documentation
    └── Placeholder.png          # Fallback 16×16 icon
```

---

## Autoloads (Singletons)

### `autoloads/Utils.gd`
Global utility + reusable presentation helpers. Available everywhere as `Utils`.
Anything that is pure geometry/math or self-contained visual juice (no dependency on
battle state) lives here, so BattleManager/BattleHUD stay focused on orchestration.

**Math / screen geometry**

| Function | Description |
|---|---|
| `manhattan(a, b) -> int` | Manhattan distance between two Vector2i positions. |
| `clamp_popup_pos(pos, size, viewport, margin) -> Vector2` | Clamps a rect to stay within viewport minus margin. |
| `popup_fits(pos, size, blocked, viewport, margin) -> bool` | True if a clamped rect overlaps none of the `blocked` rects. |
| `place_popup_rect(size, anchor, blocked, viewport, margin, pad) -> Vector2` | Tries candidate offsets around `anchor`; returns the first that fits (or first candidate). |
| `rect_fully_onscreen(pos, size, viewport, margin) -> bool` | True if a rect lies fully inside viewport minus margin. |

**Sprite sheets**

| Function | Description |
|---|---|
| `sprite_frame(texture, frame_size, frame_coords) -> Texture2D` | Extracts a frame from a sprite sheet as an `AtlasTexture`. Default frame size 32×32. |
| `random_left_column_frame(sheet, frame_size) -> AtlasTexture` | One random unique row from column 0 (delegates to `unique_left_column_frames(sheet, 1)`). |
| `unique_left_column_frames(sheet, count, frame_size) -> Array` | Shuffled unique rows from column 0; no duplicate frames within the batch. |

**Visual feedback / juice**

| Function | Description |
|---|---|
| `floating_text(text, color, world_pos, parent, font_size=14)` | Label drifts upward and fades; spawns higher with slight horizontal spread. |
| `launch_projectile(from, to, color, parent) -> Signal` | 8×8 projectile with stretch + faint trail over 0.22s. Returns `tween.finished`. |
| `damage_tier(dmg, max_hp) -> int` | Classifies a hit by % of max HP removed (0 chip … 3 massive ≥50%). Drives shake/hitstop/text scaling. |
| `shake_node(node, strength)` | Quick directional shake of a Node2D around its current position. |
| `shake_for_hit(node, dmg, max_hp, is_crit)` | Shake scaled by damage tier (+25% on crit). |
| `hitstop(duration) -> await` | Briefly drops `Engine.time_scale` to punctuate an impact, then restores it. |
| `hitstop_duration(dmg, max_hp, is_crit, is_kill) -> float` | Freeze length scaled by tier; fixed 0.12s on kills. |
| `show_damage_text(target, dmg, is_crit, weapon_mult, parent, max_hp=0)` | Scaled "-N" damage number plus CRIT! / ADVANTAGE! / WEAK! tags. |

BattleManager keeps thin private wrappers (`_shake_screen`, `_hitstop`, `_show_damage_text`,
`_shake_screen_for_hit`, `_hitstop_duration`, `_damage_tier`) that delegate here, passing
`units_layer` as the node/parent — so existing call sites are unchanged. BattleHUD's
`_clamp_popup_pos` / `_popup_fits` / `_place_popup_rect` / `_badge_fully_onscreen` likewise
delegate to the geometry helpers, passing `_viewport_size()` + its margin/pad constants.

**Constants:** `SPRITE_FRAME_SIZE = Vector2i(32, 32)`

---

### `autoloads/UITheme.gd`
Shared UI colors, font sizes, and `StyleBoxFlat` helpers. Available everywhere as `UITheme`.

| Category | Notes |
|---|---|
| Panel chrome | `PANEL_BG`, `PANEL_RADIUS`, `panel_style()`, `tinted_panel_style()`, `badge_panel_style()`, `chip_style()` |
| Typography | `FONT_XS` (8) through `FONT_DAMAGE` (22); `apply_font(label, size, color)` |
| Highlights | Move, cover, skill range, valid target, kill, telegraph, counter, hover — reduced alpha vs early prototypes |
| Terrain tints | `TERRAIN_OBSTACLE`, `TERRAIN_COVER`, `GRID_LINE` (subtle 6% white grid lines) |
| Faction accents | `HERO_ACCENT`, `ENEMY_ACCENT` |

---

### `autoloads/Combat.gd`
All combat logic. Available everywhere as `Combat`.

**Signals**
- `skill_executed(caster, targets, damage)`
- `unit_died(unit)`
- `damage_dealt(target, dmg, is_crit, weapon_mult)` — per hit; drives floating text and screen shake
- `passive_triggered(unit, text, color)` — passive VFX floating text

**Public functions (selected)**

| Function | Description |
|---|---|
| `resolve_damage(atk, atk_type, def, def_type) -> int` | Raw damage with weapon triangle multiplier. |
| `apply_skill_to_target(caster, skill, target, grid) -> Dictionary` | Single-target apply; returns `{dmg, is_crit, weapon_mult}` or `{heal}`. |
| `preview_damage` / `preview_skill_at` / `preview_skill_at_from` | Damage previews with kill/cover/weapon breakdown fields (`base_power`, `def_blocked`, `cover_blocked`, etc.). |
| `preview_heal(caster, skill, target) -> Dictionary` | `{heal, actual_heal, is_heal, target}`; caps at missing HP. |
| `skill_usable_from(caster, skill, from_pos, grid) -> bool` | Whether skill has a valid target from a given tile. |
| `can_use_skill_with_movement(caster, skill, grid) -> bool` | True if skill can hit from current tile or any reachable move tile. |
| `find_best_skill_index(caster, from_pos, target_pos, grid) -> int` | Best unused skill to hit a tile from a position. |
| `find_best_move_and_skill(caster, target_pos, grid, preferred_skill_index=-1) -> Dictionary` | `{skill_index, move_pos, target_pos}`; honors `preferred_skill_index` when set. |
| `find_move_path(from, to, grid, max_steps) -> Array[Vector2i]` | BFS path for move preview lines. |
| `get_movement_tiles` / `get_skill_target_tiles` / `get_skill_targets_at` / `get_hittable_tiles` | Range and targeting helpers. |
| `heroes_with_counter` / `linked_hero_pairs` | Counter and linked-passive queries. |
| `get_hero_counter_skill(hero, enemy) -> SkillData` | Shortest-range single-target damage skill the hero can retaliate with, or null. Single source of the counter-selection rule: the enemy-turn counter sequence calls it directly, and `_hero_has_counter_skill` (used by `heroes_with_counter`) is now just `get_hero_counter_skill(...) != null`. |
| `enemy_move_destination` | Enemy BFS toward heroes. |
| `fire_passive_turn_start` / `fire_passive_adjacency` / `fire_passive_on_damaged` | Passive triggers. |

---

### `autoloads/Heroes.gd`
Loads hero `.tres` files, randomly selects 2, assigns runtime sprites/skills/passives/equipment.

**Constants:** `HERO_SHEET = preload("res://Sprite/Placeholders/heroes.png")`

| Variable | Description |
|---|---|
| `pool` | All loaded `HeroData` resources |
| `active_heroes` | 2 heroes selected for this battle |
| `hero_sprites` | id → **unique** 32×32 `AtlasTexture` from `heroes.png` column 0 |
| `hero_skills` | id → `Array[SkillData]` (3 random skills) |
| `hero_skill_icons` | id → `Array[Texture2D]` (**6 unique** icons across both heroes' skills) |
| `hero_passive` | id → `PassiveData` |
| `hero_equipment` | id → `EquipmentData` |

Assigned in `_randomize_team()` via `Utils.unique_left_column_frames()` and `Skills.unique_icons()`.

---

### `autoloads/Enemies.gd`
Same pattern as Heroes for enemies.

**Constants:** `ENEMY_SHEET = preload("res://Sprite/Placeholders/monsters.png")`

| Variable | Description |
|---|---|
| `pool` | All loaded `EnemyData` resources |
| `active_enemies` | 2 enemies selected for this battle |
| `enemy_sprites` | id → **unique** 32×32 `AtlasTexture` from `monsters.png` column 0 |

| Function | Description |
|---|---|
| `pick_random_enemy() -> EnemyData` | Random entry from `pool` (used for reinforcement spawns). |
| `ensure_sprite(data) -> Texture2D` | Assigns a sheet frame to `enemy_sprites[id]` if missing. |

---

### `autoloads/Skills.gd`
Loads skill `.tres` files.

**Constants:** `SKILL_SHEET = preload("res://Sprite/Placeholders/Skills.png")`

| Function | Description |
|---|---|
| `random_skills(count) -> Array[SkillData]` | Shuffled pick from pool. |
| `random_icon() -> AtlasTexture` | Random single frame from column 0. |
| `unique_icons(count) -> Array` | Unique frames from column 0 for batch assignment. |

Skill icons are **not** stored on `SkillData.icon` at runtime — they live in `Heroes.hero_skill_icons`.

---

### `autoloads/Passives.gd` / `autoloads/Equipment.gd`
Load `.tres` pools; provide `random_passive()` / `random_equipment()` / `apply_bonuses()`.

---

## Battle System

### `battle/Battle.gd`
Root scene script (`Node2D`). Owns signal wiring and input.

**Important:** Connect all signals **before** `battle_manager.setup(grid, units_layer, hud)`. Call `hud.set_layout_context(self, grid)` after setup.

**Input**

| Input | Action |
|---|---|
| Left-click tile | Move, stand still, smart-cast, or confirm skill target |
| Shift+click enemy | Explicit smart cast during AWAIT_MOVE |
| Alt+click move tile | Reposition without entering skill targeting |
| Right-click / E | **End hero turn immediately** (any phase during HERO_TURN) |
| Scroll wheel / Tab | Cycle skill during AWAIT_SKILL; cycle **smart-cast preference** during AWAIT_MOVE |
| Hold Alt | Expand skill badge modifier chips (power, ADV/WEAK, DEF, Cover) |
| Mouse motion | Hover, AoE preview, skill badge preview, smart-cast preview, range glow refresh |

**Smart-cast preview** (`_update_smart_cast_preview`) during AWAIT_MOVE:
- **Enemy hover:** dashed move path, solid strike line, WILL USE badge, skill bar highlight
- **Ally hero hover:** same preview for healing skills (green tint, +HEAL badge)
- Scroll/Tab cycles smart-cast skill preference; skips spent/unreachable skills for hovered target

**Range glows** (`_refresh_range_glows`): during hero turn, enemies/allies reachable by any available skill (from current tile or reachable move tiles) get outline + soft fill glow via `hud.show_unit_glows()`.

**Highlight mode** (`_sync_highlight_mode`): clears incompatible highlight layers when switching move / skill / enemy phases.

**BattleManager → HUD signal connections**

| Signal | Handler |
|---|---|
| `state_changed` | Clear highlights / radial / unit glows |
| `movement_tiles_updated` | `show_move_highlights` + range glows |
| `skill_targets_updated` | `show_target_highlights` (skill tint) + range glows |
| `skill_valid_targets_updated` | `show_valid_target_highlights` + range glows |
| `skill_bar_requested` | `show_skill_bar` / `hide_skill_bar` |
| `active_skill_changed` | `show_active_skill_on_hero` / clear |
| `active_actor_changed` | `set_active_actor` (corner ring) |
| `turn_order_updated` | `show_turn_order` (icon timeline) |
| `status_indicators_updated` | Status icons + counter tile highlights on enemy turn |
| `enemy_telegraph_requested` / `enemy_telegraph_cleared` | Enemy telegraph overlays |
| `move_ghost_at` | `spawn_move_ghost` after unit moves |
| `radial_menu_requested` | Legacy radial (usually hidden) |

`turn_intent_updated`, `milestone_updated`, and `round_updated` are **no longer wired** (HUD stubs are no-ops).

---

### `battle/BattleManager.gd`
Core turn controller. No rendering — communicates via signals. Holds optional `hud: BattleHUD` ref for kill-flash VFX and active-ring position updates.

**Enums**
- `State`: `HERO_TURN`, `ENEMY_TURN`, `GAME_OVER`
- `HeroPhase`: `AWAIT_MOVE`, `AWAIT_SKILL_SELECT`, `AWAIT_SKILL` (no manual hero selection)
- `SkillState`: `AVAILABLE`, `NO_RANGE`, `USED`

**Key state**
- `active_hero`, `_current_skill_index`, `_processing`
- `smart_skill_preference` — `-1` = auto best skill for smart cast; `0..2` = force slot when scrolling during AWAIT_MOVE on enemy/ally hover
- `_enemy_wave_size` — count of enemies in the current wave; used for reinforcement spawn sizing
- `_turn_queue` — interleaved initiative (SPD desc); living units only
- `_last_skill_by_hero` — remembers last cast skill per hero
- `_cycle_count` — initiative cycles completed; drives escalation (no round display)

**Signals**
- `state_changed`, `hero_activated`, `hero_skills_updated`
- `movement_tiles_updated`, `skill_targets_updated`, `skill_valid_targets_updated`
- `skill_bar_requested(hero, states, highlight_index)`
- `active_skill_changed(hero, skill)`
- `active_actor_changed(unit)`
- `move_ghost_at(grid_pos, is_hero)`
- `turn_order_updated`, `milestone_updated`, `status_indicators_updated`
- `enemy_telegraph_requested` / `enemy_telegraph_cleared`
- `turn_intent_updated(text)` — still emitted internally in some paths but HUD ignores it

**Turn flow**

```
_begin_round()   # one initiative cycle
  └─ escalation (+1 enemy ATK every 3 cycles)
  └─ sort living units by SPD → _turn_queue
  └─ _advance_turn()
       ├─ hero (initiative) → _activate_hero() → AWAIT_MOVE
       │    └─ move / stand still → _enter_skill_select_phase()
       │         ├─ skill in range → _pick_auto_skill_index() → AWAIT_SKILL
       │         │    └─ click target → _cast_current_skill() [wind-up, projectile, tiered juice]
       │         │         └─ skills remain (with movement budget) → AWAIT_MOVE; else → _mark_hero_done()
       │         ├─ skill reachable after move + movement left → stay AWAIT_MOVE
       │         └─ no usable skills → _mark_hero_done()
       └─ enemy → active_actor ring → telegraph → move → attack → optional counter
  └─ queue empty → next cycle (_begin_round)
```

**Skill availability:** `_compute_skill_states()` uses `Combat.can_use_skill_with_movement()` — a skill is `AVAILABLE` if it can hit from the hero's current tile **or** any tile still reachable with `movement_remaining`. `NO_RANGE` only when unreachable even with remaining movement.

**Hero turn end:** Turn does **not** end while any unused skill remains reachable with current movement. After a skill, hero returns to AWAIT_MOVE if another skill is still usable. **Right-click / E ends immediately** from any hero phase (move or skill targeting).

**Smart click:** Hover/click enemy or ally during AWAIT_MOVE uses `get_smart_cast_plan()` → `Combat.find_best_move_and_skill(..., smart_skill_preference)`. Healing skills score via `preview_heal`.

**Enemy reinforcement:** When **all** enemies in the current wave die, spawn `_enemy_wave_size + 1` new enemies on random valid tiles (passable, empty, in bounds). `_enemy_wave_size` updates to the new wave count. Victory only if the board has no room to spawn reinforcements.

**Death handling**
- **Heroes:** `play_knocked_out_animation()` — 90° rotation, grayed, HP bar hidden; corpse stays on field; tile freed via `grid.remove_unit()`. Hero remains in `hero_units` with `hp <= 0`. If active hero dies mid-turn, `_advance_turn()` is deferred.
- **Enemies:** `play_death_animation()` → fade → `queue_free()`.

**Hero selection:** Removed. The next living hero in the SPD queue is activated automatically via `_activate_hero()`.

**Key methods**

| Method | Description |
|---|---|
| `setup(grid, units_layer, hud)` | Spawn units, connect combat signals, start cycle 1. |
| `on_tile_clicked(grid_pos, smart_cast, move_only)` | Main input entry point. |
| `on_radial_end_pressed()` | End hero turn immediately (no phase gate). |
| `get_smart_cast_plan(target_pos)` | Smart-cast plan respecting `smart_skill_preference`. |
| `cycle_smart_skill(direction, target_pos)` | Scroll/Tab during AWAIT_MOVE. |
| `cycle_skill(direction, context_target)` | AWAIT_MOVE → smart skill; AWAIT_SKILL → active skill. |
| `get_skill_states()` | Per-skill AVAILABLE / NO_RANGE / USED (movement-aware). |
| `_living_hero_count()` | Count heroes with `hp > 0`. |
| `_spawn_reinforcement_enemies(count)` | Spawns random enemies on shuffled valid tiles. |
| `_cast_current_skill(target_pos)` | Wind-up, tinted projectile, staggered AoE, kill flash, tiered hitstop/shake. |
| `_run_single_enemy_turn(enemy)` | Telegraph, move ghost, attack, counter. |

---

### `battle/Grid.gd`
16×16 logical grid; **rows 0–1 not playable** (HUD reserve). **14 playable rows** (y = 2..15). **32×32 px tiles**.

| Constant | Value |
|---|---|
| `GRID_W` / `GRID_H` | 16 |
| `GRID_ROW_MIN` | 2 |
| `TILE_SIZE` | 32 |

| Method | Description |
|---|---|
| `world_to_grid(world_pos)` | Pixel → grid cell. |
| `grid_to_world(grid_pos)` | Grid cell → **center** pixel `(x*32+16, y*32+16)`. |
| `is_in_bounds(pos)` | Requires `y >= GRID_ROW_MIN`. |
| `is_passable(pos)` | False for OBSTACLE tiles. |
| `get_cover_bonus(pos)` | +3 DEF on COVER tiles. |
| `get_tiles_in_range(origin, radius)` | Manhattan-radius tile list. |

**Visuals:** Subtle grid lines (`UITheme.GRID_LINE`); terrain uses `UITheme.TERRAIN_OBSTACLE` / `TERRAIN_COVER`. Tiles and lines only drawn for `y >= GRID_ROW_MIN`.

**Terrain:** 8 obstacles (impassable), 4 cover tiles (+3 DEF). Fixed layout; spawns always clear.

---

### `battle/units/Unit.gd`
Base class for all units.

| Method | Description |
|---|---|
| `set_body_sprite(sprite)` | Sets Body `Sprite2D` texture. |
| `get_body_texture() -> Texture2D` | Body sprite for timeline icons. |
| `update_hp_bar()` | HP bar with green / yellow / red fill by threshold; 5-step segments. |
| `move_to_world(world_pos) -> Tween` | 0.15s move tween. |
| `play_attack_windup(toward) -> Signal` | Squash + pull-back before strike. |
| `play_attack_animation(toward)` | 8px lunge + body scale pulse. |
| `play_hit_animation()` / `play_crit_hit_animation()` | Hit feedback. |
| `play_heal_animation()` / `play_buff_animation()` | Support VFX. |
| `play_death_animation(knockback_dir) -> Signal` | Knockback + fade (enemies). |
| `play_knocked_out_animation(knockback_dir) -> Signal` | Knockback + 90° rotation + gray (heroes). |

---

### `battle/units/HeroUnit.gd`

**Extra state:** `skills`, `skill_icons`, `passive`, `equipment`, `used_skills`, `movement_remaining`

| Method | Description |
|---|---|
| `setup(data)` | Stats, `Heroes.hero_sprites[id]`, skills, icons, equipment. |
| `get_skill_icon(index) -> Texture2D` | Runtime icon from `hero_skill_icons`. |
| `use_skill(index)` | Marks used; **resets `movement_remaining` to SPD**. |
| `reset_for_turn()` | Clears used skills and temp stats (living heroes only). |

---

### `battle/units/EnemyUnit.gd`

| Method | Description |
|---|---|
| `setup(data)` | Stats + `Enemies.enemy_sprites[id]`. |
| `get_skill_name() -> String` | From `EnemyData.skill_display_name`. |
| `find_attack_target_from` / `find_attack_target` | 45% weapon-advantage bias; skips dead heroes (`hp <= 0`). |
| `raw_attack_result(target) -> Dictionary` | `{dmg, is_crit, weapon_mult}`. |

---

## UI

### `ui/BattleHUD.gd` / `BattleHUD.tscn`
`CanvasLayer` child of `Battle`. Uses `_screen_popup_layer` for screen-space overlays and `HighlightLayer` for tile highlights / path lines.

**Signals:** `radial_skill_selected`, `radial_end_pressed`, `radial_skill_hovered`, `skill_bar_selected`, `skill_bar_end_pressed`

**Top chrome (timeline only)**
- Plain `Control` — **no panel background**, no instruction text, no round counter
- `TurnOrderBar`: **0.5× body sprite icons** for upcoming units (current actor slightly scaled + faction tint)
- `TimelineLine`: `Line2D` connecting icon centers behind the bar
- `show_turn_intent`, `show_round`, `show_milestone`, `show_game_over` text — **no-ops or minimal** (no HUD text)

**Skill bar (bottom right)**
- Icon-only slots (44×44) with **tooltip** = skill name
- Spent = desaturated icon + **✓** overlay; out of range = red diagonal slash
- Active slot = pulsing border glow (not scale bump)
- End button styled via `UITheme`

**Highlight layers** (`HighlightStyle`: `FILL` or `OUTLINE`)

| Layer | Style | Purpose |
|---|---|---|
| Move | Fill (green; amber on cover) | Reachable tiles |
| Skill range | Fill (skill tint, low alpha) | Selected skill range |
| Valid targets | Outline (yellow) + fill kill | Hittable unit tiles |
| Unit range glow | Outline + soft fill | Enemies/allies in attack or heal range |
| Cursor AoE | Fill | AoE splash at cursor tile |
| Telegraph | Fill + outline | Enemy move/attack preview |
| Counter | Outline | Counter-ready heroes on enemy turn |
| Hover | Outline | Interactable tiles only |
| Active actor | Pulsing corner ring | Current initiative unit; **follows unit every frame** |

**Highlight mode gating** (`set_highlight_mode`): clears incompatible layers when switching MOVE / SKILL / ENEMY phases.

**Smart-cast preview** (`show_smart_attack_preview`) — during AWAIT_MOVE when hovering an enemy or ally (heal):
- **Dashed** blue move path + **solid** strike line
- Skill range + AoE tiles (outline on AoE during preview)
- Skill bar highlights planned skill slot
- **WILL USE** badge at hovered tile with outcome preview

**Skill badges** (`ACTIVE` / `WILL USE`):
- Fixed-width panel (~152px): header strip, icon + skill name, big damage/heal number
- **Default:** modifier chips hidden; **Hold Alt** shows breakdown (power, ADV/WEAK, DEF, Cover)
- **☠ KILL** chip always visible on lethal hits
- "Hold Alt for breakdown" hint when chips collapsed
- Damage number scale-punch on change; placement via horizontal slide from anchor tile

**Popup layout API**

| Function | Description |
|---|---|
| `set_layout_context(battle, grid)` | Enables grid→screen conversion for placement. |
| `set_badge_hover_grid(grid_pos)` | Mouse-hover tile for badge anchor. |
| `show_active_skill_on_hero(hero, skill, skill_index, grid, previews)` | ACTIVE badge on hovered target. |
| `update_active_skill_badge_damage(previews)` | Refresh outcome without rebuild. |
| `show_smart_attack_preview(..., previews)` | Paths, highlights, WILL USE badge. |
| `show_unit_glows(units, color, grid)` / `clear_unit_glows()` | In-range unit highlights. |
| `set_active_actor(unit, grid)` / `update_active_actor_position(unit, grid)` | Corner ring; tracked unit updated in `_process`. |
| `spawn_move_ghost` / `play_kill_flash` | Move trail + lethal tile flash. |

**Removed from HUD:** turn intent label, round label, milestone text, cover-tile bottom-left hint, skill bar name/status labels, text-based turn order.

---

## Resources (Data Classes)

### `resources/HeroData.gd`
`id, display_name, sprite (optional/unused at runtime), base_hp/atk/def/spd, attack_type, crit_chance`

### `resources/EnemyData.gd`
`id, display_name, sprite (optional/unused), base stats, skill_range, skill_base_damage, skill_display_name, crit_chance`

### `resources/SkillData.gd`
`id, display_name, description, icon (optional/unused), icon_tint, range, base_damage, target_type, attack_type_override, use_type_override, aoe_radius`

- `target_type`: `ENEMY_SINGLE`, `ENEMY_AOE`, `ALLY_SINGLE`, `SELF`
- `base_damage < 0` = healing

| Method | Description |
|---|---|
| `get_display_tint(skill_index) -> Color` | Slot-based attack colors; green heal; blue buff. |
| `is_healing() -> bool` | `base_damage < 0` |
| `is_buff() -> bool` | SELF or non-damage ally target |

### `resources/PassiveData.gd`
- `TriggerEvent`: `ON_HIT`, `ON_KILL`, `ON_TURN_START`, `ON_ADJACENT_ALLY`, `ON_DAMAGED`
- `EffectType`: `STAT_BUFF`, `REGEN`, `COUNTER_ATTACK`, `DAMAGE_BOOST`

### `resources/EquipmentData.gd` / `resources/WeaponTriangle.gd`
Unchanged.

---

## Feature Summary

### Sprite sheets (unique runtime frames)
- **`heroes.png`** → 2 unique hero body frames (`Utils.unique_left_column_frames`)
- **`monsters.png`** → 2 unique enemy frames
- **`Skills.png`** → 6 unique skill icons (3 per hero)
- See `Sprite/Placeholders/placeholder.md`

### Hero turn flow
- **Initiative-driven** — SPD queue activates the next **living** hero
- After move or stand still → auto skill select if in range, else keep moving if skills reachable
- Turn continues until all skills **spent** or **unreachable** with remaining movement
- **Right-click / E** ends turn immediately from any hero phase
- Scroll/Tab cycles skill or smart-cast preference; Alt expands badge chips; Alt+click = move-only
- In-range enemies/allies **glow** during hero turn

### Skill visual identity
- `get_display_tint(skill_index)` ties range tiles, projectiles, skill bar borders, and glows
- ACTIVE / WILL USE badges with progressive disclosure (Alt for full math)

### Critical hits
- 10% heroes / 5% enemies default; ×1.5 damage; gold "CRIT!" text; hitstop + white flash

### Weapon triangle
- "ADVANTAGE!" / "WEAK!" floating text; gold projectiles on advantage

### Combat juice
- Attack **wind-up** before lunge/projectile
- **Damage tiering** — shake, hitstop, float size scale with % target max HP
- **Kill beat** — brief pre-flash hitstop → red tile flash + ☠ + extended hitstop
- Turn handoff white tile flash; corner ring follows active unit
- Screen shake, enemy fade-death, hero knockdown, "COUNTER!" banner
- Staggered AoE hits (0.08s apart); move **ghost** trails; projectile stretch + trail

### Counter-attacks
- Free auto-retaliation with shortest-range skill; does not consume skill charge
- Green outline on counter-ready heroes during enemy turn

### Initiative & UI
- SPD-sorted interleaved turns; **icon timeline** with connecting line (no text chrome)
- Active-actor pulsing corner ring tracks current unit position

### Enemy AI
- Path toward heroes; 45% weapon-advantage targeting; ignores knocked-out heroes
- Telegraph with move/attack intent icons before acting

### Cycle escalation
- Every **3 initiative cycles**: all living enemies +1 ATK (internal `_cycle_count`; not shown in HUD)

### Win conditions
- **Lose** if all heroes are dead (knocked out)
- **Win** if all enemies are dead and reinforcements cannot spawn (no valid empty passable in-bounds tiles)
- Reinforcement waves escalate: each full wipe spawns `previous_wave_size + 1` enemies

### Terrain
- Obstacles block movement; cover grants +3 DEF (amber move highlight on cover tiles vs green normal move)
- Top two grid rows non-playable (HUD overlap)

### Outcome preview (skill badges)
- **AWAIT_SKILL:** ACTIVE badge on hovered target — damage/heal preview; kill tile overlays
- **AWAIT_MOVE (enemy/ally hover):** WILL USE badge with same breakdown + dashed/solid path lines
