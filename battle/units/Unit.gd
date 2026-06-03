class_name Unit
extends Node2D

var grid_pos: Vector2i = Vector2i.ZERO
var hp: int = 0
var max_hp: int = 0
var attack_type: WeaponTriangle.Type = WeaponTriangle.Type.MELEE

var bonus_atk: int = 0
var bonus_def: int = 0
var bonus_spd: int = 0
var temp_atk_bonus: int = 0  # reset each turn
var crit_chance: float = 0.0

@onready var hp_bar: ProgressBar = $HPBar
@onready var label: Label = $Label

func init_stats(base_hp: int, base_atk: int, base_def: int, base_spd: int,
		atype: WeaponTriangle.Type, unit_name: String) -> void:
	max_hp = base_hp
	hp = base_hp
	bonus_atk = base_atk
	bonus_def = base_def
	bonus_spd = base_spd
	attack_type = atype
	label.text = unit_name
	update_hp_bar()
	queue_redraw()

func _draw() -> void:
	var dot_color = Color(0.9, 0.2, 0.2)
	match attack_type:
		WeaponTriangle.Type.RANGE:
			dot_color = Color(0.25, 0.85, 0.35)
		WeaponTriangle.Type.MAGE:
			dot_color = Color(0.3, 0.5, 1.0)
	draw_rect(Rect2(-16, 10, 4, 4), Color(0, 0, 0, 1))
	draw_rect(Rect2(-15, 11, 2, 2), dot_color)

func set_body_sprite(sprite: Texture2D) -> void:
	var body := get_node_or_null("Body") as Sprite2D
	if body == null or sprite == null:
		return
	body.texture = sprite
	body.modulate = Color(1, 1, 1, 1)

func get_body_texture() -> Texture2D:
	var body := get_node_or_null("Body") as Sprite2D
	if body == null:
		return null
	return body.texture

func get_atk() -> int:
	return bonus_atk + temp_atk_bonus

func get_def() -> int:
	return bonus_def

func get_spd() -> int:
	return bonus_spd

func update_hp_bar() -> void:
	if hp_bar == null:
		return
	hp_bar.max_value = max_hp
	hp_bar.value = hp
	hp_bar.step = max(1, max_hp / 5)
	var ratio := float(hp) / float(max_hp) if max_hp > 0 else 0.0
	var fill := StyleBoxFlat.new()
	fill.set_corner_radius_all(2)
	if ratio > 0.5:
		fill.bg_color = Color(0.22, 0.88, 0.38, 1.0)
	elif ratio > 0.25:
		fill.bg_color = Color(0.95, 0.82, 0.18, 1.0)
	else:
		fill.bg_color = Color(0.92, 0.22, 0.22, 1.0)
	hp_bar.add_theme_stylebox_override("fill", fill)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.08, 0.1, 0.85)
	bg.set_corner_radius_all(2)
	hp_bar.add_theme_stylebox_override("background", bg)

func reset_temp_stats() -> void:
	temp_atk_bonus = 0

func is_dead() -> bool:
	return hp <= 0

func move_to_world(world_pos: Vector2) -> Tween:
	var tween := create_tween()
	tween.tween_property(self, "position", world_pos, 0.15)
	return tween

# Wind-up before attack: slight squash and pull-back.
func play_attack_windup(toward: Vector2 = Vector2.ZERO) -> Signal:
	var body := get_node_or_null("Body") as Sprite2D
	var origin := position
	var dir := (toward - origin).normalized() if toward != Vector2.ZERO else Vector2(0, -1)
	var tween := create_tween()
	if body:
		tween.tween_property(body, "scale", Vector2(1.18, 0.88), 0.07)
	tween.parallel().tween_property(self, "position", origin - dir * 4.0, 0.07)
	if body:
		tween.tween_property(body, "scale", Vector2(1.0, 1.0), 0.05)
	tween.parallel().tween_property(self, "position", origin, 0.05)
	return tween.finished

# Quick lunge toward `toward`, then snap back. Pass Vector2.ZERO to lunge upward.
func play_attack_animation(toward: Vector2 = Vector2.ZERO) -> void:
	var body := get_node_or_null("Body") as Sprite2D
	var origin := position
	var dir := (toward - position).normalized() if toward != Vector2.ZERO else Vector2(0, -1)
	var tween := create_tween()
	tween.tween_property(self, "position", origin + dir * 8.0, 0.06)
	tween.tween_property(self, "position", origin, 0.08)
	if body:
		tween.parallel().tween_property(body, "scale", Vector2(1.08, 1.08), 0.06)
		tween.tween_property(body, "scale", Vector2(1.0, 1.0), 0.06)

# Flash red and shake when hit.
func play_hit_animation() -> void:
	var body := get_node_or_null("Body")
	var origin := position
	if body:
		var orig_color = body.modulate
		var ct := create_tween()
		ct.tween_property(body, "modulate", Color(2.2, 0.35, 0.35, 1.0), 0.07)
		ct.tween_property(body, "modulate", orig_color, 0.14)
	var pt := create_tween()
	pt.tween_property(self, "position", origin + Vector2(4.0, -1.0), 0.05)
	pt.tween_property(self, "position", origin - Vector2(3.0, 1.0), 0.05)
	pt.tween_property(self, "position", origin, 0.04)

func play_crit_hit_animation() -> void:
	var body := get_node_or_null("Body")
	if body:
		var orig_color = body.modulate
		var ct := create_tween()
		ct.tween_property(body, "modulate", Color(2.8, 2.8, 2.8, 1.0), 0.05)
		ct.tween_property(body, "modulate", orig_color, 0.12)
	play_hit_animation()

func play_heal_animation() -> void:
	var body := get_node_or_null("Body")
	if body:
		var orig_color = body.modulate
		var ct := create_tween()
		ct.tween_property(body, "modulate", Color(0.3, 1.2, 0.5, 1.0), 0.08)
		ct.tween_property(body, "modulate", orig_color, 0.18)

func play_buff_animation() -> void:
	var body := get_node_or_null("Body")
	if body:
		var orig_color = body.modulate
		var ct := create_tween()
		ct.tween_property(body, "modulate", Color(0.4, 0.7, 1.4, 1.0), 0.08)
		ct.tween_property(body, "modulate", orig_color, 0.18)

func play_death_animation(knockback_dir: Vector2 = Vector2(0, 1)) -> Signal:
	var dir := knockback_dir.normalized() if knockback_dir != Vector2.ZERO else Vector2(0, 1)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "position", position + dir * 18.0, 0.22)
	tween.tween_property(self, "modulate:a", 0.0, 0.45)
	return tween.finished

func play_knocked_out_animation(knockback_dir: Vector2 = Vector2(0, 1)) -> Signal:
	var dir := knockback_dir.normalized() if knockback_dir != Vector2.ZERO else Vector2(0, 1)
	if label:
		label.visible = false
	if hp_bar:
		hp_bar.visible = false
	set_process(false)
	set_physics_process(false)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "position", position + dir * 8.0, 0.18)
	tween.tween_property(self, "rotation", deg_to_rad(90.0), 0.22)
	tween.tween_property(self, "modulate", Color(0.42, 0.42, 0.48, 0.62), 0.22)
	return tween.finished
