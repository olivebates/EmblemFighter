extends Node

const ENEMY_SHEET := preload("res://Sprite/Placeholders/monsters.png")

var pool: Array[EnemyData] = []
var active_enemies: Array[EnemyData] = []
var enemy_sprites: Dictionary = {}  # id -> AtlasTexture

func _ready() -> void:
	var dir := DirAccess.open("res://data/enemies/")
	if dir:
		for file in dir.get_files():
			if file.ends_with(".tres"):
				var res := load("res://data/enemies/" + file) as EnemyData
				if res:
					pool.append(res)
	_randomize_enemies()

func _randomize_enemies() -> void:
	var shuffled := pool.duplicate()
	shuffled.shuffle()
	active_enemies = shuffled.slice(0, 2)
	enemy_sprites.clear()
	var enemy_frames := Utils.unique_left_column_frames(ENEMY_SHEET, active_enemies.size())
	for i in active_enemies.size():
		var enemy: EnemyData = active_enemies[i]
		if i < enemy_frames.size():
			enemy_sprites[enemy.id] = enemy_frames[i]

func pick_random_enemy() -> EnemyData:
	if pool.is_empty():
		return null
	return pool[randi() % pool.size()]

func ensure_sprite(data: EnemyData) -> Texture2D:
	if data == null:
		return null
	if enemy_sprites.has(data.id):
		return enemy_sprites[data.id]
	var frames := Utils.unique_left_column_frames(ENEMY_SHEET, pool.size())
	var idx := pool.find(data)
	if idx >= 0 and idx < frames.size():
		enemy_sprites[data.id] = frames[idx]
		return frames[idx]
	var fallback := Utils.unique_left_column_frames(ENEMY_SHEET, 1)
	if not fallback.is_empty():
		enemy_sprites[data.id] = fallback[0]
		return fallback[0]
	return null
