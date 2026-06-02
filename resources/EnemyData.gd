class_name EnemyData extends Resource

@export var id: StringName
@export var display_name: String
@export var sprite: Texture2D
@export var base_hp: int = 60
@export var base_atk: int = 12
@export var base_def: int = 6
@export var base_spd: int = 3
@export var attack_type: WeaponTriangle.Type = WeaponTriangle.Type.MELEE
@export var skill_range: int = 1
@export var skill_base_damage: float = 12.0
@export var skill_display_name: String = "Strike"
@export var crit_chance: float = 0.05
