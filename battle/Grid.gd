class_name Grid
extends Node2D

var GRID_W: int = 16
var GRID_H: int = 16
const GRID_ROW_MIN = 2  # top two rows reserved for HUD overlay
const TILE_SIZE = 32

enum TileType { NORMAL, OBSTACLE, COVER }

var occupancy: Dictionary = {}  # Vector2i -> Unit node
var terrain: Dictionary = {}    # Vector2i -> TileType
var _bg_sprite: Sprite2D = null
var _room_node: Node2D = null   # Instantiated room scene kept for TileMapLayer rendering

@onready var tile_map: TileMapLayer = $TileMapLayer

func _ready() -> void:
	_load_room_data()
	_setup_background()
	_draw_grid_lines()
	_draw_tiles()

func _load_room_data() -> void:
	var room = RoomLibrary.active_room as RoomData
	if room == null:
		_generate_default_terrain()
		return
	GRID_W = room.grid_w
	GRID_H = room.grid_h
	terrain.clear()
	for w in room.walls:
		terrain[Vector2i(int(w.x), int(w.y))] = TileType.OBSTACLE
	for c in room.covers:
		terrain[Vector2i(int(c.x), int(c.y))] = TileType.COVER

	# Instantiate room scene so its TileMapLayers render in-game
	if RoomLibrary.active_room_packed != null:
		_room_node = RoomLibrary.active_room_packed.instantiate() as Node2D
		# z_index -5: above background (-10), below grid lines (-2)
		_room_node.z_index = -5
		# Hide editor-only overlay nodes
		for n in ["GridBounds", "HeroSpawn", "EnemySpawn"]:
			var child = _room_node.get_node_or_null(n)
			if child:
				child.visible = false
		add_child(_room_node)

func _generate_default_terrain() -> void:
	GRID_W = 16
	GRID_H = 16
	var obstacles = [
		Vector2i(3, 4), Vector2i(12, 4),
		Vector2i(7, 7), Vector2i(8, 7),
		Vector2i(7, 8), Vector2i(8, 8),
		Vector2i(3, 11), Vector2i(12, 11),
	]
	var covers = [
		Vector2i(5, 5), Vector2i(10, 5),
		Vector2i(5, 9), Vector2i(10, 9),
	]
	for pos in obstacles:
		terrain[pos] = TileType.OBSTACLE
	for pos in covers:
		terrain[pos] = TileType.COVER

func reload_room() -> void:
	# Clear old room scene
	if is_instance_valid(_room_node):
		_room_node.queue_free()
	_room_node = null
	# Clear background
	if is_instance_valid(_bg_sprite):
		_bg_sprite.queue_free()
	_bg_sprite = null
	# Clear grid lines
	var lines_node = find_child("GridLines")
	if lines_node:
		lines_node.queue_free()
	# Clear any leftover ColorRects (fallback terrain from default room)
	for child in get_children():
		if child is ColorRect:
			child.queue_free()
	tile_map.clear()
	occupancy.clear()
	terrain.clear()
	_load_room_data()
	_setup_background()
	_draw_grid_lines()
	_draw_tiles()

func _setup_background() -> void:
	var room = RoomLibrary.active_room as RoomData
	if room == null or room.background_texture == null:
		return
	var bg = Sprite2D.new()
	bg.name = "Background"
	bg.texture = room.background_texture
	bg.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	bg.region_enabled = true
	var margin = 10 * TILE_SIZE
	bg.region_rect = Rect2(0, 0, (GRID_W + 20) * TILE_SIZE, (GRID_H + 20) * TILE_SIZE)
	bg.centered = false
	bg.position = Vector2(-margin, -margin)
	bg.z_index = -10
	add_child(bg)
	_bg_sprite = bg

func _draw_grid_lines() -> void:
	var layer = Node2D.new()
	layer.name = "GridLines"
	layer.z_index = -2
	add_child(layer)
	var board_w = GRID_W * TILE_SIZE
	var board_h = GRID_H * TILE_SIZE
	for x in range(GRID_W + 1):
		var line = Line2D.new()
		line.points = PackedVector2Array([
			Vector2(x * TILE_SIZE, 0),
			Vector2(x * TILE_SIZE, board_h),
		])
		line.default_color = UITheme.GRID_LINE
		line.width = 1.0
		line.antialiased = false
		layer.add_child(line)
	for y in range(GRID_ROW_MIN, GRID_H + 1):
		var line = Line2D.new()
		line.points = PackedVector2Array([
			Vector2(0, y * TILE_SIZE),
			Vector2(board_w, y * TILE_SIZE),
		])
		line.default_color = UITheme.GRID_LINE
		line.width = 1.0
		line.antialiased = false
		layer.add_child(line)

func _draw_tiles() -> void:
	if is_instance_valid(_room_node):
		# Room scene TileMapLayers handle all visual rendering — no ColorRects needed
		return
	# Fallback for default terrain (no room scene)
	for x in GRID_W:
		for y in range(GRID_ROW_MIN, GRID_H):
			tile_map.set_cell(Vector2i(x, y), 0, Vector2i(0, 0))
	for pos in terrain:
		var rect = ColorRect.new()
		rect.size = Vector2(TILE_SIZE, TILE_SIZE)
		rect.position = grid_to_world(pos) - Vector2(TILE_SIZE / 2.0, TILE_SIZE / 2.0)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		match terrain[pos]:
			TileType.OBSTACLE:
				rect.color = UITheme.TERRAIN_OBSTACLE
			TileType.COVER:
				rect.color = UITheme.TERRAIN_COVER
		add_child(rect)

func is_passable(pos: Vector2i) -> bool:
	return terrain.get(pos, TileType.NORMAL) != TileType.OBSTACLE

func get_cover_bonus(pos: Vector2i) -> int:
	return 3 if terrain.get(pos, TileType.NORMAL) == TileType.COVER else 0

func world_to_grid(world_pos: Vector2) -> Vector2i:
	return Vector2i(int(world_pos.x / TILE_SIZE), int(world_pos.y / TILE_SIZE))

func grid_to_world(grid_pos: Vector2i) -> Vector2:
	return Vector2(grid_pos.x * TILE_SIZE + TILE_SIZE / 2.0, grid_pos.y * TILE_SIZE + TILE_SIZE / 2.0)

func is_in_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < GRID_W and pos.y >= GRID_ROW_MIN and pos.y < GRID_H

func is_empty(pos: Vector2i) -> bool:
	return not occupancy.has(pos)

func get_unit_at(pos: Vector2i) -> Node:
	return occupancy.get(pos, null)

func place_unit(unit: Node, pos: Vector2i) -> void:
	occupancy[pos] = unit
	unit.grid_pos = pos
	unit.position = grid_to_world(pos)

func move_unit(unit: Node, to: Vector2i) -> void:
	if occupancy.get(unit.grid_pos) == unit:
		occupancy.erase(unit.grid_pos)
	occupancy[to] = unit
	unit.grid_pos = to

func remove_unit(unit: Node) -> void:
	if occupancy.get(unit.grid_pos) == unit:
		occupancy.erase(unit.grid_pos)

func get_tiles_in_range(origin: Vector2i, radius: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for x in range(origin.x - radius, origin.x + radius + 1):
		for y in range(origin.y - radius, origin.y + radius + 1):
			var pos = Vector2i(x, y)
			if is_in_bounds(pos) and Utils.manhattan(origin, pos) <= radius:
				result.append(pos)
	return result

func get_adjacent_units(pos: Vector2i, group: String) -> Array:
	var result = []
	for neighbor in [pos + Vector2i(1,0), pos + Vector2i(-1,0), pos + Vector2i(0,1), pos + Vector2i(0,-1)]:
		var u = get_unit_at(neighbor)
		if u and u.is_in_group(group):
			result.append(u)
	return result
