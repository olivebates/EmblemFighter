@tool
class_name GridBounds
extends Node2D

const TILE_SIZE = 32

@export var grid_cols: int = 16 :
	set(v):
		grid_cols = maxi(1, v)
		queue_redraw()
		_notify_parent()

@export var grid_rows: int = 16 :
	set(v):
		grid_rows = maxi(1, v)
		queue_redraw()
		_notify_parent()


func _ready() -> void:
	position = Vector2.ZERO
	if not Engine.is_editor_hint():
		visible = false


func _notification(what: int) -> void:
	# Lock position to origin — grid always starts at (0,0)
	if what == NOTIFICATION_TRANSFORM_CHANGED and Engine.is_editor_hint():
		if position != Vector2.ZERO:
			position = Vector2.ZERO


func _draw() -> void:
	var w = grid_cols * TILE_SIZE
	var h = grid_rows * TILE_SIZE
	# Outer boundary
	draw_rect(Rect2(0, 0, w, h), Color(0.9, 0.9, 0.9, 0.15))
	draw_rect(Rect2(0, 0, w, h), Color(0.85, 0.85, 0.85, 0.8), false, 2.0)
	# Corner resize hint
	var handle = 10.0
	draw_rect(Rect2(w - handle, h - handle, handle, handle), Color(0.85, 0.85, 0.85, 0.8))
	# Label
	var font = ThemeDB.fallback_font
	var label = "GRID  %d x %d" % [grid_cols, grid_rows]
	draw_string(font, Vector2(4, 12), label, HORIZONTAL_ALIGNMENT_LEFT, w - 8, 10, Color(1, 1, 1, 0.7))


func _notify_parent() -> void:
	if Engine.is_editor_hint() and get_parent() and get_parent().has_method("queue_redraw"):
		get_parent().queue_redraw()
