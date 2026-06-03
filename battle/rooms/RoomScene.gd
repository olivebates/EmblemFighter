@tool
extends Node2D

## Paint tiles on the child TileMapLayer nodes to design the room:
##   FloorLayer  — visual floor tiles (aesthetic only)
##   WallLayer   — impassable obstacle tiles
##   CoverLayer  — passable tiles that grant +3 DEF
##
## Drag HeroSpawn / EnemySpawn rectangles to set spawn zones.
## Resize GridBounds to set the playable area.
## Duplicate Room1.tscn to create new rooms — every .tscn in this folder
## is automatically added to the random room pool.

const TILE_SIZE = 32

## Texture tiled across the area 10 tiles outside the grid in every direction.
@export var background_texture: Texture2D :
	set(v):
		background_texture = v
		queue_redraw()

## Which enemies spawn on this level and how many of each.
## Leave empty to fall back to random enemy selection.
@export var enemy_spawns: Array[EnemySpawnConfig] = []


func _get_grid_dims() -> Vector2i:
	for child in get_children():
		if child is GridBounds:
			return Vector2i((child as GridBounds).grid_cols, (child as GridBounds).grid_rows)
	return Vector2i(16, 16)


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	_draw_grid_guides()


func _draw_grid_guides() -> void:
	var dims = _get_grid_dims()
	var gw = dims.x
	var gh = dims.y
	var margin = 10 * TILE_SIZE

	# Tiled background extending 10 tiles beyond the grid
	if background_texture != null:
		draw_texture_rect(background_texture,
			Rect2(-margin, -margin, (gw + 20) * TILE_SIZE, (gh + 20) * TILE_SIZE),
			true)

	# Subtle grid background so the area is visible behind unpainted TileMapLayers
	draw_rect(Rect2(0, 0, gw * TILE_SIZE, gh * TILE_SIZE), Color(0.14, 0.14, 0.20, 0.6))
	# Dimmer HUD rows
	draw_rect(Rect2(0, 0, gw * TILE_SIZE, 2 * TILE_SIZE), Color(0.07, 0.07, 0.11, 0.7))

	# Grid lines
	var line_col = Color(0.28, 0.28, 0.42, 0.45)
	for x in range(gw + 1):
		draw_line(
			Vector2(x * TILE_SIZE, 0),
			Vector2(x * TILE_SIZE, gh * TILE_SIZE),
			line_col, 1.0
		)
	for y in range(gh + 1):
		draw_line(
			Vector2(0, y * TILE_SIZE),
			Vector2(gw * TILE_SIZE, y * TILE_SIZE),
			line_col, 1.0
		)

	# HUD boundary line
	draw_line(
		Vector2(0, 2 * TILE_SIZE),
		Vector2(gw * TILE_SIZE, 2 * TILE_SIZE),
		Color(1.0, 0.85, 0.2, 0.7), 2.0
	)


func to_room_data() -> RoomData:
	var r = RoomData.new()
	var dims = _get_grid_dims()
	r.grid_w = dims.x
	r.grid_h = dims.y
	r.background_texture = background_texture
	r.enemy_spawns = enemy_spawns.duplicate()

	# Read walls and covers from TileMapLayer children
	var wall_layer = get_node_or_null("WallLayer") as TileMapLayer
	if wall_layer:
		for pos in wall_layer.get_used_cells():
			r.walls.append({"x": pos.x, "y": pos.y})

	var cover_layer = get_node_or_null("CoverLayer") as TileMapLayer
	if cover_layer:
		for pos in cover_layer.get_used_cells():
			r.covers.append({"x": pos.x, "y": pos.y})

	# Read spawn zones from SpawnZone children
	for child in get_children():
		if child is SpawnZone:
			var rect = (child as SpawnZone).get_spawn_rect_tiles()
			if (child as SpawnZone).zone_type == SpawnZone.ZoneType.HERO:
				r.hero_spawn = rect
			else:
				r.enemy_spawn = rect

	return r
