@tool
class_name SpawnZone
extends Node2D

enum ZoneType { HERO, ENEMY }

const TILE_SIZE = 32

@export var zone_type: ZoneType = ZoneType.HERO :
	set(v):
		zone_type = v
		queue_redraw()

@export var grid_cols: int = 10 :
	set(v):
		grid_cols = maxi(1, v)
		queue_redraw()

@export var grid_rows: int = 4 :
	set(v):
		grid_rows = maxi(1, v)
		queue_redraw()


func _ready() -> void:
	set_notify_transform(true)
	if not Engine.is_editor_hint():
		visible = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and Engine.is_editor_hint():
		# Snap position to tile grid
		var snapped = position.snapped(Vector2(TILE_SIZE, TILE_SIZE))
		if snapped != position:
			position = snapped


func _draw() -> void:
	var w = grid_cols * TILE_SIZE
	var h = grid_rows * TILE_SIZE
	var fill_color: Color
	var border_color: Color
	var label_text: String

	if zone_type == ZoneType.HERO:
		fill_color = Color(0.25, 0.50, 1.0, 0.25)
		border_color = Color(0.45, 0.72, 1.0, 0.9)
		label_text = "HERO SPAWN"
	else:
		fill_color = Color(1.0, 0.28, 0.28, 0.25)
		border_color = Color(1.0, 0.45, 0.45, 0.9)
		label_text = "ENEMY SPAWN"

	draw_rect(Rect2(0, 0, w, h), fill_color)
	draw_rect(Rect2(0, 0, w, h), border_color, false, 2.0)

	# Corner resize hint box
	var handle = 10.0
	draw_rect(Rect2(w - handle, h - handle, handle, handle), border_color)

	# Label
	if w >= 32 and h >= 16:
		var font = ThemeDB.fallback_font
		var fsize = 11
		draw_string(font, Vector2(4, fsize + 2), label_text, HORIZONTAL_ALIGNMENT_LEFT, w - 8, fsize, Color(1, 1, 1, 0.9))


func get_spawn_rect_tiles() -> Rect2i:
	var tile_x = int(position.x / TILE_SIZE)
	var tile_y = int(position.y / TILE_SIZE)
	return Rect2i(tile_x, tile_y, grid_cols, grid_rows)
