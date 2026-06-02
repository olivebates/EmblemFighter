extends Node

const SKILL_SHEET := preload("res://Sprite/Placeholders/Skills.png")

var pool: Array[SkillData] = []

func _ready() -> void:
	var dir := DirAccess.open("res://data/skills/")
	if dir:
		for file in dir.get_files():
			if file.ends_with(".tres"):
				var res := load("res://data/skills/" + file) as SkillData
				if res:
					pool.append(res)

func get_by_id(id: StringName) -> SkillData:
	for s in pool:
		if s.id == id:
			return s
	return null

func random_skills(count: int) -> Array[SkillData]:
	var shuffled := pool.duplicate()
	shuffled.shuffle()
	return shuffled.slice(0, mini(count, shuffled.size()))

func random_icon() -> AtlasTexture:
	return Utils.random_left_column_frame(SKILL_SHEET)

func unique_icons(count: int) -> Array:
	return Utils.unique_left_column_frames(SKILL_SHEET, count)
