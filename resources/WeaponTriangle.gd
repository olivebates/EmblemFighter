class_name WeaponTriangle

enum Type { MELEE, RANGE, MAGE }

# Mage > Melee > Range > Mage
static func get_multiplier(attacker: Type, defender: Type) -> float:
	if attacker == defender:
		return 1.0
	if (attacker == Type.MAGE and defender == Type.MELEE) or \
	   (attacker == Type.MELEE and defender == Type.RANGE) or \
	   (attacker == Type.RANGE and defender == Type.MAGE):
		return 1.2
	return 0.8
