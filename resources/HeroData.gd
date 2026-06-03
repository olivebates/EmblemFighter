class_name HeroData extends Resource

@export var id: StringName
@export var display_name: String
@export var sprite: Texture2D
@export var base_hp: int = 80
@export var base_atk: int = 15
@export var base_def: int = 8
@export var base_spd: int = 3
@export var attack_type: WeaponTriangle.Type = WeaponTriangle.Type.MELEE
@export var crit_chance: float = 0.10
@export var op_buff_name: String = ""
@export var op_buff_description: String = ""
@export var op_buff_type: String = ""
@export var op_buff_value: float = 0.0
