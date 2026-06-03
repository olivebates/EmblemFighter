extends Node

var owned_heroes: Array[HeroData] = []

var deployed_ids: Array[StringName] = [&"", &"", &"", &""]

# Slot-based loadouts — keyed by deployment slot index (0-3), not hero ID.
# If a hero is swapped out, the slot keeps its items.
var slot_skills_map: Dictionary = {}       # slot_idx -> Array[SkillData]   (size 4)
var slot_skill_icons_map: Dictionary = {}  # slot_idx -> Array[Texture2D]
var slot_passive_map: Dictionary = {}      # slot_idx -> Array[PassiveData] (size 4)
var slot_equipment_map: Dictionary = {}    # slot_idx -> Array[EquipmentData] (size 4)

var item_pool_skills: Array[SkillData] = []
var item_pool_passives: Array[PassiveData] = []
var item_pool_equipment: Array[EquipmentData] = []

# Resource -> Texture2D, covers all skills/passives/equipment (consistent everywhere)
var item_icons: Dictionary = {}

var hero_hp: Dictionary = {}    # id -> int  (-1 = use max)
var hero_ko: Dictionary = {}    # id -> bool
var hero_mana: Dictionary = {}  # id -> int  (-1 = use max)

# Upgrade tokens, earned only by dismantling items of the matching type.
var gear_tokens: int = 0
var skill_tokens: int = 0
var passive_tokens: int = 0

func _ready() -> void:
	_initialize()

func _initialize() -> void:
	var pool_copy = Heroes.pool.duplicate()
	pool_copy.shuffle()
	for i in mini(3, pool_copy.size()):
		owned_heroes.append(pool_copy[i])

	var frames = Utils.unique_left_column_frames(Heroes.HERO_SHEET, owned_heroes.size())
	for i in owned_heroes.size():
		if i < frames.size():
			Heroes.hero_sprites[owned_heroes[i].id] = frames[i]

	var all_skills = Skills.pool.duplicate()
	all_skills.shuffle()
	var all_passives = Passives.pool.duplicate()
	all_passives.shuffle()
	var all_equips = Equipment.pool.duplicate()
	all_equips.shuffle()

	var skill_idx = 0
	var passive_idx = 0
	var equip_idx = 0

	# Distribute items across the first 3 deployment slots (matching owned hero count at start).
	for slot in mini(3, owned_heroes.size()):
		var skill_slots: Array[SkillData] = [null, null, null, null]
		for j in 2:
			if skill_idx < all_skills.size():
				skill_slots[j] = all_skills[skill_idx]
				skill_idx += 1
		slot_skills_map[slot] = skill_slots

		var passive_slots: Array[PassiveData] = [null, null, null, null]
		if passive_idx < all_passives.size():
			passive_slots[0] = all_passives[passive_idx]
			passive_idx += 1
		slot_passive_map[slot] = passive_slots

		var equip_slots: Array[EquipmentData] = [null, null, null, null]
		if equip_idx < all_equips.size():
			equip_slots[0] = all_equips[equip_idx]
			equip_idx += 1
		slot_equipment_map[slot] = equip_slots

	# Slot 3 starts empty
	slot_skills_map[3] = [null, null, null, null]
	slot_passive_map[3] = [null, null, null, null]
	slot_equipment_map[3] = [null, null, null, null]

	# Remainder goes to pools
	while skill_idx < all_skills.size():
		item_pool_skills.append(all_skills[skill_idx])
		skill_idx += 1
	while passive_idx < all_passives.size():
		item_pool_passives.append(all_passives[passive_idx])
		passive_idx += 1
	while equip_idx < all_equips.size():
		item_pool_equipment.append(all_equips[equip_idx])
		equip_idx += 1

	for hero in owned_heroes:
		hero_hp[hero.id] = -1
		hero_ko[hero.id] = false
		hero_mana[hero.id] = -1

	_assign_all_icons()
	_add_test_grade_items()
	_rebuild_all_skill_icon_maps()

	for i in mini(2, owned_heroes.size()):
		deployed_ids[i] = owned_heroes[i].id

	sync_to_heroes()

# ── Team management ───────────────────────────────────────────────────────────

func get_deployed_heroes() -> Array[HeroData]:
	var result: Array[HeroData] = []
	for id in deployed_ids:
		if id == &"":
			continue
		var h = get_hero_by_id(id)
		if h != null:
			result.append(h)
	return result

func get_hero_by_id(id: StringName) -> HeroData:
	for h in owned_heroes:
		if h.id == id:
			return h
	return null

func set_slot(slot_idx: int, hero_id: StringName) -> void:
	if slot_idx < 0 or slot_idx >= 4:
		return
	for i in deployed_ids.size():
		if deployed_ids[i] == hero_id:
			deployed_ids[i] = &""
	deployed_ids[slot_idx] = hero_id
	sync_to_heroes()

func clear_slot(slot_idx: int) -> void:
	if slot_idx < 0 or slot_idx >= 4:
		return
	deployed_ids[slot_idx] = &""
	sync_to_heroes()

func can_start_round() -> bool:
	for id in deployed_ids:
		if id == &"":
			continue
		if not hero_ko.get(id, false):
			return true
	return false

# ── Item equipping (slot-based) ───────────────────────────────────────────────

func equip_skill(deploy_slot: int, item_slot: int, new_skill: SkillData) -> void:
	var slots = slot_skills_map.get(deploy_slot, [null, null, null, null])
	if item_slot >= slots.size():
		return
	var old = slots[item_slot]
	if old != null:
		item_pool_skills.append(old)
	item_pool_skills.erase(new_skill)
	slots[item_slot] = new_skill
	slot_skills_map[deploy_slot] = slots
	_rebuild_skill_icons_for(deploy_slot)
	sync_to_heroes()

func unequip_skill(deploy_slot: int, item_slot: int) -> void:
	var slots = slot_skills_map.get(deploy_slot, [null, null, null, null])
	if item_slot >= slots.size():
		return
	var old = slots[item_slot]
	if old != null:
		item_pool_skills.append(old)
		slots[item_slot] = null
	slot_skills_map[deploy_slot] = slots
	_rebuild_skill_icons_for(deploy_slot)
	sync_to_heroes()

func equip_passive(deploy_slot: int, item_slot: int, new_passive: PassiveData) -> void:
	var slots = slot_passive_map.get(deploy_slot, [null, null, null, null])
	if item_slot >= slots.size():
		return
	var old = slots[item_slot]
	if old != null:
		item_pool_passives.append(old)
	item_pool_passives.erase(new_passive)
	slots[item_slot] = new_passive
	slot_passive_map[deploy_slot] = slots
	sync_to_heroes()

func unequip_passive(deploy_slot: int, item_slot: int) -> void:
	var slots = slot_passive_map.get(deploy_slot, [null, null, null, null])
	if item_slot >= slots.size():
		return
	var old = slots[item_slot]
	if old != null:
		item_pool_passives.append(old)
		slots[item_slot] = null
	slot_passive_map[deploy_slot] = slots
	sync_to_heroes()

func equip_equipment(deploy_slot: int, item_slot: int, new_equip: EquipmentData) -> void:
	var slots = slot_equipment_map.get(deploy_slot, [null, null, null, null])
	if item_slot >= slots.size():
		return
	var old = slots[item_slot]
	if old != null:
		item_pool_equipment.append(old)
	item_pool_equipment.erase(new_equip)
	slots[item_slot] = new_equip
	slot_equipment_map[deploy_slot] = slots
	sync_to_heroes()

func unequip_equipment(deploy_slot: int, item_slot: int) -> void:
	var slots = slot_equipment_map.get(deploy_slot, [null, null, null, null])
	if item_slot >= slots.size():
		return
	var old = slots[item_slot]
	if old != null:
		item_pool_equipment.append(old)
		slots[item_slot] = null
	slot_equipment_map[deploy_slot] = slots
	sync_to_heroes()

# Returns all non-null equipped items of a given mode across all deployment slots.
func get_all_equipped_items(mode: String) -> Array:
	var result: Array = []
	for slot in 4:
		var slots: Array = []
		match mode:
			"skill":    slots = slot_skills_map.get(slot, [])
			"passive":  slots = slot_passive_map.get(slot, [])
			"equipment": slots = slot_equipment_map.get(slot, [])
		for item in slots:
			if item != null and not result.has(item):
				result.append(item)
	return result

# Returns { "deploy_slot": int, "item_slot": int } or {} if not found.
func find_item_location(mode: String, item: Resource) -> Dictionary:
	if item == null:
		return {}
	for deploy_slot in 4:
		var slots: Array = []
		match mode:
			"skill":    slots = slot_skills_map.get(deploy_slot, [])
			"passive":  slots = slot_passive_map.get(deploy_slot, [])
			"equipment": slots = slot_equipment_map.get(deploy_slot, [])
		for i in slots.size():
			if slots[i] == item:
				return {"deploy_slot": deploy_slot, "item_slot": i}
	return {}

# Move an item from wherever it is to the specified slot, displacing old occupant.
func move_item_to_slot(dest_deploy: int, mode: String, dest_item_slot: int, item: Resource) -> void:
	if item == null:
		return
	var loc = find_item_location(mode, item)
	if loc.has("deploy_slot"):
		var src_deploy: int = loc.deploy_slot
		var src_item_slot: int = loc.item_slot
		if src_deploy == dest_deploy and src_item_slot == dest_item_slot:
			return
		match mode:
			"skill":
				var src_slots = slot_skills_map.get(src_deploy, [null, null, null, null])
				if src_item_slot < src_slots.size():
					src_slots[src_item_slot] = null
					slot_skills_map[src_deploy] = src_slots
					_rebuild_skill_icons_for(src_deploy)
			"passive":
				var src_slots = slot_passive_map.get(src_deploy, [null, null, null, null])
				if src_item_slot < src_slots.size():
					src_slots[src_item_slot] = null
					slot_passive_map[src_deploy] = src_slots
			"equipment":
				var src_slots = slot_equipment_map.get(src_deploy, [null, null, null, null])
				if src_item_slot < src_slots.size():
					src_slots[src_item_slot] = null
					slot_equipment_map[src_deploy] = src_slots
	match mode:
		"skill":     equip_skill(dest_deploy, dest_item_slot, item as SkillData)
		"passive":   equip_passive(dest_deploy, dest_item_slot, item as PassiveData)
		"equipment": equip_equipment(dest_deploy, dest_item_slot, item as EquipmentData)

# ── Grade upgrades & dismantling (token economy) ──────────────────────────────

func get_tokens(mode: String) -> int:
	match mode:
		"equipment": return gear_tokens
		"skill":     return skill_tokens
		"passive":   return passive_tokens
	return 0

func _add_tokens(mode: String, n: int) -> void:
	match mode:
		"equipment": gear_tokens += n
		"skill":     skill_tokens += n
		"passive":   passive_tokens += n

func _pool_for(mode: String) -> Array:
	match mode:
		"skill":     return item_pool_skills
		"passive":   return item_pool_passives
		"equipment": return item_pool_equipment
	return []

# Raise an item's grade by one. Gated only by the token balance — no cap.
func upgrade_item(mode: String, item: Resource) -> bool:
	if item == null:
		return false
	var cost = Grade.upgrade_cost(item.grade)
	if get_tokens(mode) < cost:
		return false
	_add_tokens(mode, -cost)
	item.grade += 1
	if mode == "skill":
		var loc = find_item_location("skill", item)
		if loc.has("deploy_slot"):
			_rebuild_skill_icons_for(loc.deploy_slot)
	sync_to_heroes()
	return true

# Destroy an UNEQUIPPED (pool) item for tokens. Equipped items are refused.
func dismantle_item(mode: String, item: Resource) -> bool:
	if item == null:
		return false
	if not find_item_location(mode, item).is_empty():
		return false  # equipped — not dismantlable
	var pool = _pool_for(mode)
	if not pool.has(item):
		return false
	_add_tokens(mode, Grade.dismantle_yield(item.grade))
	pool.erase(item)
	item_icons.erase(item)
	sync_to_heroes()
	return true

# Dismantle every unequipped item of a type. Returns how many were dismantled.
func dismantle_all_unequipped(mode: String) -> int:
	var pool = _pool_for(mode)
	var count = pool.size()
	for item in pool.duplicate():
		_add_tokens(mode, Grade.dismantle_yield(item.grade))
		item_icons.erase(item)
	pool.clear()
	sync_to_heroes()
	return count

# ── Between-round state ───────────────────────────────────────────────────────

func save_battle_state(hero_units: Array) -> void:
	for unit in hero_units:
		if not is_instance_valid(unit):
			continue
		var id = unit.hero_data.id
		hero_hp[id] = unit.hp
		hero_ko[id] = unit.hp <= 0
		if "mana" in unit:
			hero_mana[id] = unit.mana

# ── Sync to Heroes autoload ───────────────────────────────────────────────────

func sync_to_heroes() -> void:
	Heroes.active_heroes = get_deployed_heroes()
	for i in 4:
		var hero_id = deployed_ids[i]
		if hero_id == &"":
			continue

		var filtered_skills: Array[SkillData] = []
		for s in slot_skills_map.get(i, []):
			if s != null:
				filtered_skills.append(s)
		Heroes.hero_skills[hero_id] = filtered_skills
		Heroes.hero_skill_icons[hero_id] = slot_skill_icons_map.get(i, [])

		var filtered_passives: Array[PassiveData] = []
		for p in slot_passive_map.get(i, []):
			if p != null:
				filtered_passives.append(p)
		Heroes.hero_passive[hero_id] = filtered_passives

		var filtered_equips: Array[EquipmentData] = []
		for e in slot_equipment_map.get(i, []):
			if e != null:
				filtered_equips.append(e)
		Heroes.hero_equipment[hero_id] = filtered_equips

# ── Icon management ───────────────────────────────────────────────────────────

func _add_test_grade_items() -> void:
	var equip_base = Equipment.pool[0] if not Equipment.pool.is_empty() else null
	var skill_base = Skills.pool[0] if not Skills.pool.is_empty() else null
	var passive_base = Passives.pool[0] if not Passives.pool.is_empty() else null
	var new_items: Array = []
	for g in range(1, 22):  # grades 1 through 21 (Infinite +2)
		if equip_base:
			var e = equip_base.duplicate() as EquipmentData
			e.grade = g
			item_pool_equipment.append(e)
			new_items.append(e)
		if skill_base:
			var s = skill_base.duplicate() as SkillData
			s.grade = g
			item_pool_skills.append(s)
			new_items.append(s)
		if passive_base:
			var p = passive_base.duplicate() as PassiveData
			p.grade = g
			item_pool_passives.append(p)
			new_items.append(p)
	for item in new_items:
		item_icons[item] = Skills.random_icon()

func _assign_all_icons() -> void:
	var all_items: Array = []
	for slot in 4:
		for s in slot_skills_map.get(slot, []):
			if s != null and not all_items.has(s):
				all_items.append(s)
	for s in item_pool_skills:
		if not all_items.has(s):
			all_items.append(s)
	for slot in 4:
		for p in slot_passive_map.get(slot, []):
			if p != null and not all_items.has(p):
				all_items.append(p)
	for p in item_pool_passives:
		if not all_items.has(p):
			all_items.append(p)
	for slot in 4:
		for e in slot_equipment_map.get(slot, []):
			if e != null and not all_items.has(e):
				all_items.append(e)
	for e in item_pool_equipment:
		if not all_items.has(e):
			all_items.append(e)
	var icons = Utils.unique_left_column_frames(Skills.SKILL_SHEET, all_items.size())
	for i in mini(all_items.size(), icons.size()):
		item_icons[all_items[i]] = icons[i]

func _rebuild_all_skill_icon_maps() -> void:
	for slot in 4:
		_rebuild_skill_icons_for(slot)

func _rebuild_skill_icons_for(deploy_slot: int) -> void:
	var slots = slot_skills_map.get(deploy_slot, [])
	var icons: Array[Texture2D] = []
	for s in slots:
		if s != null:
			var icon = item_icons.get(s, null)
			if icon:
				icons.append(icon)
			else:
				icons.append(Skills.random_icon())
	slot_skill_icons_map[deploy_slot] = icons
