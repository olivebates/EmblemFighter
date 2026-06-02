extends Node

var pool: Array[EquipmentData] = []

func _ready() -> void:
	var dir := DirAccess.open("res://data/equipment/")
	if dir:
		for file in dir.get_files():
			if file.ends_with(".tres"):
				var res := load("res://data/equipment/" + file) as EquipmentData
				if res:
					pool.append(res)

func get_by_id(id: StringName) -> EquipmentData:
	for e in pool:
		if e.id == id:
			return e
	return null

func random_equipment() -> EquipmentData:
	if pool.is_empty():
		return null
	return pool[randi() % pool.size()]

func apply_bonuses(unit: Node, equip: EquipmentData) -> void:
	unit.bonus_atk += equip.atk_bonus
	unit.bonus_def += equip.def_bonus
	unit.bonus_spd += equip.spd_bonus
	unit.max_hp += equip.hp_bonus
	unit.hp += equip.hp_bonus
