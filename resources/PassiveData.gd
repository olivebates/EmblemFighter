class_name PassiveData extends Resource

enum TriggerEvent { ON_HIT, ON_KILL, ON_TURN_START, ON_ADJACENT_ALLY, ON_DAMAGED }
enum EffectType { STAT_BUFF, REGEN, COUNTER_ATTACK, DAMAGE_BOOST }

@export var id: StringName
@export var display_name: String
@export var description: String
@export var trigger_event: TriggerEvent = TriggerEvent.ON_TURN_START
@export var effect_type: EffectType = EffectType.STAT_BUFF
@export var effect_value: float = 0.0
