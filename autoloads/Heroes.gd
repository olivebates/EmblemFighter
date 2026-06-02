extends Node

const HERO_SHEET := preload("res://Sprite/Placeholders/heroes.png")

var pool: Array[HeroData] = []
var active_heroes: Array[HeroData] = []
var hero_skills: Dictionary = {}    # id -> Array[SkillData]
var hero_skill_icons: Dictionary = {}  # id -> Array[Texture2D]
var hero_sprites: Dictionary = {}   # id -> AtlasTexture
var hero_passive: Dictionary = {}   # id -> PassiveData
var hero_equipment: Dictionary = {} # id -> EquipmentData

func _ready() -> void:
	var dir := DirAccess.open("res://data/heroes/")
	if dir:
		for file in dir.get_files():
			if file.ends_with(".tres"):
				var res := load("res://data/heroes/" + file) as HeroData
				if res:
					pool.append(res)
	_randomize_team()

func _randomize_team() -> void:
	var shuffled := pool.duplicate()
	shuffled.shuffle()
	active_heroes = shuffled.slice(0, 2)
	hero_sprites.clear()
	hero_skill_icons.clear()
	var hero_frames := Utils.unique_left_column_frames(HERO_SHEET, active_heroes.size())
	var icon_count := 0
	for hero in active_heroes:
		hero_skills[hero.id] = Skills.random_skills(3)
		icon_count += hero_skills[hero.id].size()
	var skill_frames := Skills.unique_icons(icon_count)
	var icon_idx := 0
	for i in active_heroes.size():
		var hero: HeroData = active_heroes[i]
		if i < hero_frames.size():
			hero_sprites[hero.id] = hero_frames[i]
		var icons: Array[Texture2D] = []
		for _j in hero_skills[hero.id].size():
			if icon_idx < skill_frames.size():
				icons.append(skill_frames[icon_idx])
			icon_idx += 1
		hero_skill_icons[hero.id] = icons
		hero_passive[hero.id] = Passives.random_passive()
		hero_equipment[hero.id] = Equipment.random_equipment()
