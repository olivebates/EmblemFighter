extends Node

var pool: Array[PassiveData] = []

func _ready() -> void:
	var dir := DirAccess.open("res://data/passives/")
	if dir:
		for file in dir.get_files():
			if file.ends_with(".tres"):
				var res := load("res://data/passives/" + file) as PassiveData
				if res:
					pool.append(res)

func get_by_id(id: StringName) -> PassiveData:
	for p in pool:
		if p.id == id:
			return p
	return null

func random_passive() -> PassiveData:
	if pool.is_empty():
		return null
	return pool[randi() % pool.size()]
