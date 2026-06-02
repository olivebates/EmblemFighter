# Sprite Sheets

All unit and skill visuals use **unique** frames from the **leftmost column** (32×32) of each sheet—no duplicate rows within a battle group:

| Sheet | Used for | Size | Left-column frames |
|---|---|---|---|
| `heroes.png` | Active heroes | 224×224 | 7 |
| `monsters.png` | Active enemies | 384×416 | 13 |
| `Skills.png` | Hero skill icons | 352×832 | 26 |

## Runtime assignment

- `Heroes._randomize_team()` → `Utils.unique_left_column_frames(heroes.png, 2)`; skill icons via `Skills.unique_icons(6)`
- `Enemies._randomize_enemies()` → `Utils.unique_left_column_frames(monsters.png, 2)`

Frames are extracted via `Utils.sprite_frame()` / `Utils.unique_left_column_frames()` at 32×32.
