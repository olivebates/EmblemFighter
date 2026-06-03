class_name StatusEffectData extends Resource

enum EffectType { ATK_UP, REGEN, SHIELD, ATK_DOWN, POISON, SLOW }

@export var id: StringName
@export var display_name: String
@export var description: String
@export var duration: int = 2
@export var is_debuff: bool = false
@export var effect_type: EffectType = EffectType.ATK_UP
@export var effect_value: float = 5.0
@export var color: Color = Color(0.4, 1.0, 0.5)

func get_detail_text() -> String:
	match effect_type:
		EffectType.ATK_UP:
			return "Increases attack by %d for the duration." % int(effect_value)
		EffectType.REGEN:
			return "Restores %d HP at the start of each turn." % int(effect_value)
		EffectType.SHIELD:
			return "Reduces all incoming damage by %d%%." % int(effect_value)
		EffectType.ATK_DOWN:
			return "Reduces attack by %d for the duration." % int(effect_value)
		EffectType.POISON:
			return "Deals %d damage at the start of each enemy turn." % int(effect_value)
		EffectType.SLOW:
			return "Reduces movement range by %d tiles." % int(effect_value)
		_:
			return description
