extends Node

var effects: Array = []
var _skill_effects: Dictionary = {}

func _ready() -> void:
	_define_effects()
	call_deferred("_assign_to_skills")

func _define_effects() -> void:
	var atk_up = StatusEffectData.new()
	atk_up.id = &"atk_up"
	atk_up.display_name = "ATK UP"
	atk_up.description = "Increases the target's attack power for the duration."
	atk_up.duration = 2
	atk_up.is_debuff = false
	atk_up.effect_type = StatusEffectData.EffectType.ATK_UP
	atk_up.effect_value = 5.0
	atk_up.color = Color(1.0, 0.72, 0.2)

	var regen = StatusEffectData.new()
	regen.id = &"regen"
	regen.display_name = "REGEN"
	regen.description = "Restores HP at the start of each turn."
	regen.duration = 3
	regen.is_debuff = false
	regen.effect_type = StatusEffectData.EffectType.REGEN
	regen.effect_value = 8.0
	regen.color = Color(0.28, 1.0, 0.52)

	var shield = StatusEffectData.new()
	shield.id = &"shield"
	shield.display_name = "SHIELD"
	shield.description = "Reduces all incoming damage by 20%."
	shield.duration = 2
	shield.is_debuff = false
	shield.effect_type = StatusEffectData.EffectType.SHIELD
	shield.effect_value = 20.0
	shield.color = Color(0.45, 0.78, 1.0)

	var atk_down = StatusEffectData.new()
	atk_down.id = &"atk_down"
	atk_down.display_name = "ATK DOWN"
	atk_down.description = "Reduces the target's attack power for the duration."
	atk_down.duration = 2
	atk_down.is_debuff = true
	atk_down.effect_type = StatusEffectData.EffectType.ATK_DOWN
	atk_down.effect_value = 5.0
	atk_down.color = Color(1.0, 0.35, 0.35)

	var poison = StatusEffectData.new()
	poison.id = &"poison"
	poison.display_name = "POISON"
	poison.description = "Deals damage at the start of each enemy turn."
	poison.duration = 3
	poison.is_debuff = true
	poison.effect_type = StatusEffectData.EffectType.POISON
	poison.effect_value = 6.0
	poison.color = Color(0.62, 0.2, 0.88)

	var slow = StatusEffectData.new()
	slow.id = &"slow"
	slow.display_name = "SLOW"
	slow.description = "Reduces movement range by 2 tiles."
	slow.duration = 2
	slow.is_debuff = true
	slow.effect_type = StatusEffectData.EffectType.SLOW
	slow.effect_value = 2.0
	slow.color = Color(0.38, 0.72, 1.0)

	effects = [atk_up, regen, shield, atk_down, poison, slow]

func _assign_to_skills() -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = 1337
	for skill in Skills.pool:
		var n = rng.randi_range(0, 2)
		if n == 0:
			continue
		var available = effects.duplicate()
		var chosen: Array = []
		for _i in n:
			if available.is_empty():
				break
			var idx = rng.randi() % available.size()
			chosen.append(available[idx])
			available.remove_at(idx)
		_skill_effects[skill] = chosen

func get_effects_for_skill(skill: SkillData) -> Array:
	if skill == null:
		return []
	return _skill_effects.get(skill, [])
