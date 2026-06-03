extends Node

const ROOMS_DIR = "res://battle/rooms/"

var _room_scenes: Array = []      # Array[PackedScene], sorted by filename
var active_room: RoomData = null
var active_room_packed: PackedScene = null
var current_room_index: int = 0

func _ready() -> void:
	_scan_rooms()
	_apply_room(0)

func _scan_rooms() -> void:
	_room_scenes.clear()
	var dir = DirAccess.open(ROOMS_DIR)
	if dir == null:
		return
	var files: Array = []
	dir.list_dir_begin()
	var fname = dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".tscn"):
			files.append(fname)
		fname = dir.get_next()
	dir.list_dir_end()
	files.sort()  # alphabetical: Room1, Room2, Room3 …
	for f in files:
		var scene = load(ROOMS_DIR + f) as PackedScene
		if scene:
			_room_scenes.append(scene)

func _apply_room(index: int) -> void:
	if _room_scenes.is_empty():
		active_room = RoomData.new()
		active_room_packed = null
		return
	var scene = _room_scenes[index] as PackedScene
	active_room_packed = scene
	var node = scene.instantiate()
	if node.has_method("to_room_data"):
		active_room = node.to_room_data()
	else:
		active_room = RoomData.new()
	node.queue_free()

func pick_next_room() -> void:
	if _room_scenes.is_empty():
		return
	current_room_index = (current_room_index + 1) % _room_scenes.size()
	_apply_room(current_room_index)
