extends Node

const SPRITE_FRAME_SIZE := Vector2i(32, 32)

func manhattan(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)

func sprite_frame(texture: Texture2D, frame_size: Vector2i = SPRITE_FRAME_SIZE,
		frame_coords: Vector2i = Vector2i.ZERO) -> Texture2D:
	if texture == null:
		return null
	if texture.get_width() <= frame_size.x and texture.get_height() <= frame_size.y:
		return texture
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = Rect2(
		frame_coords.x * frame_size.x,
		frame_coords.y * frame_size.y,
		frame_size.x,
		frame_size.y
	)
	return atlas

func random_left_column_frame(sheet: Texture2D,
		frame_size: Vector2i = SPRITE_FRAME_SIZE) -> AtlasTexture:
	var frames := unique_left_column_frames(sheet, 1, frame_size)
	if frames.is_empty():
		return null
	return frames[0] as AtlasTexture

func unique_left_column_frames(sheet: Texture2D, count: int,
		frame_size: Vector2i = SPRITE_FRAME_SIZE) -> Array:
	if sheet == null or count <= 0:
		return []
	var rows := sheet.get_height() / frame_size.y
	if rows <= 0:
		return []
	var pick_count := mini(count, rows)
	var row_indices: Array[int] = []
	for row in rows:
		row_indices.append(row)
	row_indices.shuffle()
	var frames: Array = []
	for i in pick_count:
		var row: int = row_indices[i]
		frames.append(sprite_frame(sheet, frame_size, Vector2i(0, row)))
	return frames

# Spawns a label at world_pos that drifts upward and fades out.
func floating_text(text: String, color: Color, world_pos: Vector2, parent: Node, font_size: int = 14) -> void:
	var label := Label.new()
	label.text = text
	label.modulate = color
	label.add_theme_font_size_override("font_size", font_size)
	var spread := float(text.hash() % 7) - 3.0
	label.position = world_pos + Vector2(-12.0 + spread * 6.0, -30.0 - font_size * 0.5)
	label.z_index = 20
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)

	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 40.0, 2.0)
	tween.tween_property(label, "modulate:a", 0.0, 2.0).set_delay(0.7)
	tween.finished.connect(label.queue_free)

func launch_projectile(from: Vector2, to: Vector2, color: Color, parent: Node) -> Signal:
	var proj := ColorRect.new()
	proj.color = color
	proj.size = Vector2(8, 8)
	proj.pivot_offset = Vector2(4, 4)
	proj.position = from - Vector2(4, 4)
	proj.mouse_filter = Control.MOUSE_FILTER_IGNORE
	proj.z_index = 15
	parent.add_child(proj)

	var trail := ColorRect.new()
	trail.color = Color(color.r, color.g, color.b, color.a * 0.35)
	trail.size = Vector2(5, 5)
	trail.position = from - Vector2(2.5, 2.5)
	trail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	trail.z_index = 14
	parent.add_child(trail)

	var tween := proj.create_tween()
	tween.tween_property(proj, "position", to - Vector2(4, 4), 0.22)
	var scale_tw := proj.create_tween()
	scale_tw.tween_property(proj, "scale", Vector2(0.65, 1.35), 0.11)
	scale_tw.tween_property(proj, "scale", Vector2.ONE, 0.11)
	var trail_tween := trail.create_tween()
	trail_tween.set_parallel(true)
	trail_tween.tween_property(trail, "position", to - Vector2(2.5, 2.5), 0.22)
	trail_tween.tween_property(trail, "modulate:a", 0.0, 0.22)
	tween.finished.connect(func():
		proj.queue_free()
		trail.queue_free()
	)
	return tween.finished

# --- Hit feedback / juice ---

# Classifies a hit by fraction of the target's max HP it removed.
# 0 = chip, 1 = light, 2 = heavy, 3 = massive (>= 50%). Used to scale
# screen shake, hitstop, and damage-text size consistently.
func damage_tier(dmg: int, max_hp: int) -> int:
	if max_hp <= 0:
		return 0
	var pct := float(dmg) / float(max_hp)
	if pct >= 0.5:
		return 3
	if pct >= 0.25:
		return 2
	if pct >= 0.1:
		return 1
	return 0

# Quick directional shake of a node around its current position.
func shake_node(node: Node2D, strength: int) -> void:
	if node == null:
		return
	var intensity := clampf(float(strength) * 0.35, 2.0, 14.0)
	var origin := node.position
	var t := node.create_tween()
	t.tween_property(node, "position", origin + Vector2(intensity, -intensity * 0.5), 0.04)
	t.tween_property(node, "position", origin + Vector2(-intensity * 0.6, intensity * 0.4), 0.04)
	t.tween_property(node, "position", origin, 0.05)

# Briefly slows time to punctuate an impact, then restores the prior scale.
# The timer ignores time_scale so it still fires while the world is slowed.
func hitstop(duration: float) -> void:
	var prev := Engine.time_scale
	Engine.time_scale = 0.05
	await get_tree().create_timer(duration, true, false, true).timeout
	Engine.time_scale = prev

# How long to freeze the game on a hit, scaled by how big the hit was.
func hitstop_duration(dmg: int, max_hp: int, is_crit: bool, is_kill: bool) -> float:
	if is_kill:
		return 0.12
	var tier := damage_tier(dmg, max_hp)
	var base = [0.04, 0.06, 0.08, 0.1][tier]
	if is_crit:
		base += 0.03
	return base

# Shakes `node` with a strength scaled by the hit's damage tier.
func shake_for_hit(node: Node2D, dmg: int, max_hp: int, is_crit: bool) -> void:
	var tier := damage_tier(dmg, max_hp)
	var mult = [0.5, 1.0, 1.45, 2.1][tier]
	if is_crit:
		mult *= 1.25
	shake_node(node, int(dmg * mult))

# --- Screen-space popup placement ---
# Pure geometry helpers for positioning popups/badges so they stay on screen
# and avoid a set of blocked rects. Callers pass viewport size + margins so the
# math has no hidden dependency on any particular node.

# Clamps `pos` so a `popup_size` rect stays within `viewport` minus `margin`.
func clamp_popup_pos(pos: Vector2, popup_size: Vector2, viewport: Vector2, margin: float) -> Vector2:
	pos.x = clampf(pos.x, margin, viewport.x - popup_size.x - margin)
	pos.y = clampf(pos.y, margin, viewport.y - popup_size.y - margin)
	return pos

# True if a clamped popup rect at `pos` overlaps none of the `blocked` rects.
func popup_fits(pos: Vector2, popup_size: Vector2, blocked: Array[Rect2],
		viewport: Vector2, margin: float) -> bool:
	var r := Rect2(clamp_popup_pos(pos, popup_size, viewport, margin), popup_size)
	for b in blocked:
		if r.intersects(b):
			return false
	return true

# Tries the standard candidate offsets around `anchor` and returns the first
# clamped position that fits; falls back to the first candidate if none fit.
func place_popup_rect(popup_size: Vector2, anchor: Vector2, blocked: Array[Rect2],
		viewport: Vector2, margin: float, pad: float) -> Vector2:
	var candidates: Array[Vector2] = [
		anchor + Vector2(pad, pad),
		anchor + Vector2(pad, -popup_size.y - pad),
		anchor + Vector2(-popup_size.x - pad, pad),
		anchor + Vector2(-popup_size.x - pad, -popup_size.y - pad),
		anchor + Vector2(-popup_size.x * 0.5, -popup_size.y - pad),
		anchor + Vector2(-popup_size.x * 0.5, pad),
	]
	for pos in candidates:
		if popup_fits(pos, popup_size, blocked, viewport, margin):
			return clamp_popup_pos(pos, popup_size, viewport, margin)
	return clamp_popup_pos(candidates[0], popup_size, viewport, margin)

# True if a `popup_size` rect at `pos` lies fully inside `viewport` minus `margin`.
func rect_fully_onscreen(pos: Vector2, popup_size: Vector2, viewport: Vector2, margin: float) -> bool:
	return (pos.x >= margin
			and pos.y >= margin
			and pos.x + popup_size.x <= viewport.x - margin
			and pos.y + popup_size.y <= viewport.y - margin)

# Floating combat text: scaled "-N" damage number, plus CRIT! / ADVANTAGE! / WEAK! tags.
func show_damage_text(target: Node, dmg: int, is_crit: bool, weapon_mult: float,
		parent: Node, max_hp: int = 0) -> void:
	var tier := damage_tier(dmg, max_hp)
	var size := clampi(12 + dmg / 4 + tier * 2, 12, 36)
	var color := Color(1.0, 0.35, 0.35)
	if is_crit:
		color = Color(1.0, 0.92, 0.15)
		size = mini(size + 6, 34)
		floating_text("CRIT!", Color(1.0, 0.92, 0.15), target.position + Vector2(0, -20), parent, 15)
	floating_text("-%d" % dmg, color, target.position, parent, size)
	if weapon_mult > 1.0:
		floating_text("ADVANTAGE!", Color(1.0, 0.85, 0.1, 0.9), target.position + Vector2(0, -10), parent, 11)
	elif weapon_mult < 1.0:
		floating_text("WEAK!", Color(0.5, 0.6, 1.0, 0.9), target.position + Vector2(0, -10), parent, 11)
