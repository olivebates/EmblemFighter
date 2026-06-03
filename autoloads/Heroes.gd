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
	# PlayerInventory loads after this and populates active_heroes + loadout dicts
