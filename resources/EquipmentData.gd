class_name EquipmentData extends Resource

@export var id: StringName
@export var display_name: String
@export var description: String
@export var atk_bonus: int = 0
@export var def_bonus: int = 0
@export var spd_bonus: int = 0
@export var hp_bonus: int = 0
@export var block_pct: float = 0.0
@export var grade: int = 1

# Stat bonuses scale by grade^2 (grade 1 = x1). No speed items exist.
func eff_atk() -> int:
	return atk_bonus * Grade.stat_mult(grade)

func eff_def() -> int:
	return def_bonus * Grade.stat_mult(grade)

func eff_hp() -> int:
	return hp_bonus * Grade.stat_mult(grade)

# Block scales LINEARLY: grade% (grade 1 = 1%, grade 2 = 2%, ...).
# block_pct in the .tres is just a flag (> 0) marking "this is a block item".
# Per-hero total is capped at 30% in Equipment.apply_bonuses.
func eff_block_pct() -> float:
	return grade * 0.01 if block_pct > 0.0 else 0.0
