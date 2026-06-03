class_name RoomData
extends Resource

var room_name: String = "Room"
var grid_w: int = 16
var grid_h: int = 16
var walls: Array = []   # Array of {x, y} dicts
var covers: Array = []  # Array of {x, y} dicts
var hero_spawn: Rect2i = Rect2i(3, 10, 10, 4)
var enemy_spawn: Rect2i = Rect2i(3, 2, 10, 4)
var background_texture: Texture2D = null
var enemy_spawns: Array = []  # Array[EnemySpawnConfig]

func to_dict() -> Dictionary:
	return {
		"room_name": room_name,
		"grid_w": grid_w,
		"grid_h": grid_h,
		"walls": walls.duplicate(true),
		"covers": covers.duplicate(true),
		"hero_spawn": {"x": hero_spawn.position.x, "y": hero_spawn.position.y, "w": hero_spawn.size.x, "h": hero_spawn.size.y},
		"enemy_spawn": {"x": enemy_spawn.position.x, "y": enemy_spawn.position.y, "w": enemy_spawn.size.x, "h": enemy_spawn.size.y},
	}

static func from_dict(d: Dictionary) -> RoomData:
	var r = RoomData.new()
	r.room_name = d.get("room_name", "Room")
	r.grid_w = int(d.get("grid_w", 16))
	r.grid_h = int(d.get("grid_h", 16))
	r.walls = d.get("walls", []).duplicate(true)
	r.covers = d.get("covers", []).duplicate(true)
	var hs = d.get("hero_spawn", {"x": 3, "y": 10, "w": 10, "h": 4})
	r.hero_spawn = Rect2i(int(hs.x), int(hs.y), int(hs.w), int(hs.h))
	var es = d.get("enemy_spawn", {"x": 3, "y": 2, "w": 10, "h": 4})
	r.enemy_spawn = Rect2i(int(es.x), int(es.y), int(es.w), int(es.h))
	return r
