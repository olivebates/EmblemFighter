class_name VictoryMenu
extends CanvasLayer

signal next_round_pressed

const PANEL_W = 880
const PANEL_H = 480
const PANEL_X = 40
const PANEL_Y = 30
const LOADOUT_SLOT_SIZE = 56
const PICKER_ICON_SIZE = 60

var _panel: Panel
var _active_tab = 0
var _tab_team: Control
var _tab_loadout: Control
var _tab_forge: Control
var _next_btn: Button
var _tab_btns: Array = []
var _tab_content: Control
var _tab_anim_tween: Tween = null

# Tab 3 — Forge
var _forge_mode: String = "equipment"
var _dismantle_all_presses: int = 0
var _forge_token_lbl: Label = null
var _dismantle_all_btn: Button = null
var _forge_grid: GridContainer = null
var _forge_cards: Dictionary = {}  # item Resource -> PanelContainer
var _root_ctrl: Control = null      # top-level control; dot particles are added here
var _displayed_tokens: int = 0      # animated display value for token label
var _undo_btn: Button = null
var _undo_item: Resource = null
var _undo_mode: String = ""
var _undo_yield: int = 0
var _undo_icon: Texture2D = null

# Tab 2 — slot-based loadout
var _selected_slot_idx: int = 0
var _slot_selector_row: HBoxContainer
var _loadout_detail: Control
var _loadout_slot_btns: Dictionary = {} # "%d|%s|%d" % [deploy_slot, mode, item_slot] -> Button

# Picker state
var _picker_overlay: ColorRect
var _picker_panel: Panel
var _picker_title_lbl: Label
var _picker_grid: GridContainer
var _picker_mode: String = ""
var _picker_item_slot: int = -1    # index within the slot's 4-item array
var _picker_deploy_slot: int = -1  # deployment slot (0-3)

# Tooltip
var _tooltip_panel: PanelContainer
var _tooltip_content: VBoxContainer
var _tooltip_visible: bool = false

func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	visible = false

func _process(_delta: float) -> void:
	if _tooltip_visible and _tooltip_panel.visible:
		_position_tooltip(get_viewport().get_mouse_position())

func show_menu() -> void:
	_refresh_all()
	visible = true
	_panel.position = Vector2(PANEL_X, PANEL_Y - 540)
	var tw = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_panel, "position", Vector2(PANEL_X, PANEL_Y), 0.45)

# ── Build ─────────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	var root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	_root_ctrl = root

	var dim = ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.62)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(_on_backdrop_clicked)
	root.add_child(dim)

	_panel = Panel.new()
	_panel.position = Vector2(PANEL_X, PANEL_Y)
	_panel.size = Vector2(PANEL_W, PANEL_H)
	_panel.add_theme_stylebox_override("panel",
		UITheme.panel_style(UITheme.PANEL_BG_DARK, UITheme.PANEL_BORDER_DARK, 8, 2))
	root.add_child(_panel)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 6)
	vbox.offset_left = 14
	vbox.offset_top = 12
	vbox.offset_right = -14
	vbox.offset_bottom = -12
	_panel.add_child(vbox)

	var tab_bar = HBoxContainer.new()
	tab_bar.add_theme_constant_override("separation", 4)
	tab_bar.custom_minimum_size = Vector2(0, 34)
	vbox.add_child(tab_bar)
	for i in 3:
		var btn = Button.new()
		btn.text = ["Team", "Loadout", "Forge"][i]
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.focus_mode = Control.FOCUS_NONE
		var idx = i
		btn.pressed.connect(func(): _switch_tab(idx))
		UITheme.apply_button_theme(btn)
		_add_press_punch(btn)
		tab_bar.add_child(btn)
		_tab_btns.append(btn)

	var content = Control.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(content)
	_tab_content = content

	_tab_team = Control.new()
	_tab_team.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.add_child(_tab_team)

	_tab_loadout = Control.new()
	_tab_loadout.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tab_loadout.visible = false
	content.add_child(_tab_loadout)

	_tab_forge = Control.new()
	_tab_forge.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tab_forge.visible = false
	content.add_child(_tab_forge)

	var bottom = HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 10)
	bottom.custom_minimum_size = Vector2(0, 44)
	vbox.add_child(bottom)

	# Undo button — Junk-grade styling, left-aligned, only visible on Forge tab
	_undo_btn = Button.new()
	_undo_btn.focus_mode = Control.FOCUS_NONE
	_undo_btn.custom_minimum_size = Vector2(44, 38)
	_undo_btn.text = "↩"
	_undo_btn.visible = false
	var _undo_sb = UITheme.panel_style(Grade.bg_color(1), Grade.outline_color(1), 4, 2)
	_undo_btn.add_theme_stylebox_override("normal", _undo_sb)
	_undo_btn.add_theme_stylebox_override("hover",
		UITheme.panel_style(Grade.bg_color(1).lightened(0.12), Grade.outline_color(1), 4, 2))
	_undo_btn.add_theme_stylebox_override("pressed", _undo_sb)
	_undo_btn.add_theme_stylebox_override("focus", _undo_sb)
	_undo_btn.add_theme_stylebox_override("disabled",
		UITheme.panel_style(Grade.bg_color(1), Grade.outline_color(1).darkened(0.4), 4, 1))
	_undo_btn.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
	_undo_btn.add_theme_font_size_override("font_size", 18)
	_add_press_punch(_undo_btn)
	_undo_btn.pressed.connect(_on_undo_pressed)
	_undo_btn.mouse_entered.connect(func():
		if _undo_item != null:
			_show_forge_btn_tip("Undo dismantle (refunds %d tokens)" % _undo_yield, UITheme.TEXT_SUBTLE)
		else:
			_show_forge_btn_tip("Nothing to undo", UITheme.TEXT_MUTED))
	_undo_btn.mouse_exited.connect(_hide_tooltip)
	bottom.add_child(_undo_btn)

	# Token label — centered in the expanding spacer to the left of dismantle-all
	var token_spacer = Control.new()
	token_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(token_spacer)

	_forge_token_lbl = Label.new()
	_forge_token_lbl.add_theme_font_size_override("font_size", 12)
	_forge_token_lbl.add_theme_color_override("font_color", UITheme.TEXT_SUBTLE)
	_forge_token_lbl.set_anchors_preset(Control.PRESET_CENTER)
	_forge_token_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_forge_token_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_forge_token_lbl.visible = false
	token_spacer.add_child(_forge_token_lbl)

	# Dismantle all unequipped — only visible on Forge tab, right side before Next Round
	_dismantle_all_btn = Button.new()
	_dismantle_all_btn.focus_mode = Control.FOCUS_NONE
	_dismantle_all_btn.custom_minimum_size = Vector2(0, 38)
	_dismantle_all_btn.text = _dismantle_all_label()
	UITheme.apply_button_theme(_dismantle_all_btn)
	_dismantle_all_btn.add_theme_color_override("font_color", UITheme.ENEMY_ACCENT)
	for _state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var _sb = _dismantle_all_btn.get_theme_stylebox(_state) as StyleBoxFlat
		if _sb != null:
			_sb.content_margin_left  = 18.0
			_sb.content_margin_right = 18.0
	_add_press_punch(_dismantle_all_btn)
	_dismantle_all_btn.pressed.connect(func(): _on_dismantle_all_pressed(_dismantle_all_btn))
	_dismantle_all_btn.mouse_entered.connect(_show_dismantle_all_tip)
	_dismantle_all_btn.mouse_exited.connect(_hide_tooltip)
	_dismantle_all_btn.visible = false
	bottom.add_child(_dismantle_all_btn)

	_next_btn = Button.new()
	_next_btn.text = "Next Round  →"
	_next_btn.custom_minimum_size = Vector2(170, 38)
	_next_btn.focus_mode = Control.FOCUS_NONE
	_next_btn.pressed.connect(_on_next_round_pressed)
	UITheme.apply_button_theme(_next_btn, false, UITheme.PANEL_RADIUS)
	_add_press_punch(_next_btn)
	bottom.add_child(_next_btn)

	_build_picker(root)
	_build_tooltip(root)
	_update_tab_style()

func _build_picker(parent: Control) -> void:
	_picker_overlay = ColorRect.new()
	_picker_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_picker_overlay.color = Color(0, 0, 0, 0.55)
	_picker_overlay.visible = false
	_picker_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_picker_overlay.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_close_picker()
	)
	parent.add_child(_picker_overlay)

	_picker_panel = Panel.new()
	_picker_panel.size = Vector2(640, 380)
	_picker_panel.position = Vector2(160, 80)
	_picker_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_picker_panel.add_theme_stylebox_override("panel",
		UITheme.panel_style(UITheme.PANEL_BG_DARK, UITheme.PANEL_BORDER_DARK, 6, 2))
	_picker_panel.gui_input.connect(func(event: InputEvent): get_viewport().set_input_as_handled())
	_picker_overlay.add_child(_picker_panel)

	var pvbox = VBoxContainer.new()
	pvbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	pvbox.add_theme_constant_override("separation", 6)
	pvbox.offset_left = 10
	pvbox.offset_top = 8
	pvbox.offset_right = -10
	pvbox.offset_bottom = -8
	_picker_panel.add_child(pvbox)

	var header = HBoxContainer.new()
	pvbox.add_child(header)
	_picker_title_lbl = Label.new()
	_picker_title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_picker_title_lbl.add_theme_font_size_override("font_size", 14)
	_picker_title_lbl.add_theme_color_override("font_color", UITheme.TEXT_PRIMARY)
	header.add_child(_picker_title_lbl)
	var close_btn = Button.new()
	close_btn.text = "  ×  "
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(_close_picker)
	UITheme.apply_button_theme(close_btn)
	_add_press_punch(close_btn)
	header.add_child(close_btn)

	pvbox.add_child(UITheme.menu_separator())

	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pvbox.add_child(scroll)
	_picker_grid = GridContainer.new()
	_picker_grid.columns = 5
	_picker_grid.add_theme_constant_override("h_separation", 8)
	_picker_grid.add_theme_constant_override("v_separation", 8)
	_picker_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_picker_grid)

func _build_tooltip(parent: Control) -> void:
	_tooltip_panel = PanelContainer.new()
	_tooltip_panel.visible = false
	_tooltip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_tooltip_panel.custom_minimum_size = Vector2(210, 0)
	var tps = UITheme.panel_style(UITheme.PANEL_BG_DARK, UITheme.PANEL_BORDER_ACCENT, 5, 2)
	tps.set_content_margin_all(10)
	_tooltip_panel.add_theme_stylebox_override("panel", tps)
	_tooltip_content = VBoxContainer.new()
	_tooltip_content.add_theme_constant_override("separation", 4)
	_tooltip_content.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_tooltip_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip_panel.add_child(_tooltip_content)
	parent.add_child(_tooltip_panel)

# ── Animation helpers ─────────────────────────────────────────────────────────

func _add_press_punch(btn: Button) -> void:
	btn.button_down.connect(func():
		btn.pivot_offset = btn.size / 2
		var tw = btn.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(btn, "scale", Vector2(1.07, 1.07), 0.07)
		tw.tween_property(btn, "scale", Vector2(1.0, 1.0), 0.1)
	)

func _add_card_tilt(card: Button) -> void:
	card.mouse_entered.connect(func():
		card.pivot_offset = card.size / 2
		var tilt = 1.5 if card.get_local_mouse_position().x > card.size.x / 2 else -1.5
		var tw = card.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(card, "rotation_degrees", tilt, 0.12)
	)
	card.mouse_exited.connect(func():
		var tw = card.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(card, "rotation_degrees", 0.0, 0.15)
	)

func _show_picker_animated() -> void:
	_picker_overlay.visible = true
	_picker_panel.pivot_offset = _picker_panel.size / 2
	_picker_panel.scale = Vector2(0.88, 0.88)
	var tw = _picker_panel.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_picker_panel, "scale", Vector2(1.0, 1.0), 0.22)

func _pulse_next_button() -> void:
	var tw = _next_btn.create_tween().set_trans(Tween.TRANS_SINE)
	tw.tween_property(_next_btn, "modulate", Color(UITheme.TEXT_PRIMARY.r, UITheme.TEXT_PRIMARY.g, UITheme.TEXT_PRIMARY.b, 1.0) * 1.05, 0.18)
	tw.tween_property(_next_btn, "modulate", Color.WHITE, 0.28)

func _add_dim_breath(dim: ColorRect) -> void:
	var tw = dim.create_tween().set_loops()
	tw.tween_property(dim, "color:a", 0.58, 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(dim, "color:a", 0.68, 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _punch_control(ctrl: Control, scale_up: float = 1.08, t_in: float = 0.07, t_out: float = 0.11) -> void:
	if ctrl == null:
		return
	ctrl.pivot_offset = ctrl.size / 2
	var tw = ctrl.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(ctrl, "scale", Vector2(scale_up, scale_up), t_in)
	tw.tween_property(ctrl, "scale", Vector2(1.0, 1.0), t_out)

func _flash_slot(deploy_slot: int, mode: String, item_slot: int) -> void:
	var key = "%d|%s|%d" % [deploy_slot, mode, item_slot]
	if not _loadout_slot_btns.has(key):
		return
	var btn = _loadout_slot_btns[key] as Button
	if btn == null or not is_instance_valid(btn):
		return
	_punch_control(btn, 1.06, 0.06, 0.1)
	var tw = btn.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	var start = btn.modulate
	btn.modulate = Color.WHITE * 1.15
	tw.tween_property(btn, "modulate", start, 0.22)

# ── Tooltip ───────────────────────────────────────────────────────────────────

func _clear_tooltip_content() -> void:
	for c in _tooltip_content.get_children():
		c.free()

func _tt_header(name_text: String, icon: Texture2D = null, color: Color = UITheme.TEXT_PRIMARY) -> void:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if icon != null:
		var tex = TextureRect.new()
		tex.texture = icon
		tex.custom_minimum_size = Vector2(22, 22)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(tex)
	var lbl = Label.new()
	lbl.text = name_text
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", color)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(lbl)
	_tooltip_content.add_child(row)

func _tt_separator() -> void:
	var sep = UITheme.menu_separator()
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip_content.add_child(sep)

func _tt_stat_row(label_text: String, value_text: String, label_color: Color = UITheme.TEXT_SUBTLE, value_color: Color = UITheme.TEXT_PRIMARY) -> void:
	var row = HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lbl = Label.new()
	lbl.text = label_text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", label_color)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(lbl)
	var val = Label.new()
	val.text = value_text
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val.add_theme_font_size_override("font_size", 11)
	val.add_theme_color_override("font_color", value_color)
	val.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(val)
	_tooltip_content.add_child(row)

func _tt_grade_subtitle(item: Resource) -> void:
	var g: int = item.grade
	var mode = ""
	if item is EquipmentData: mode = "equipment"
	elif item is SkillData:   mode = "skill"
	elif item is PassiveData: mode = "passive"
	var equipped = mode != "" and not PlayerInventory.find_item_location(mode, item).is_empty()
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gl = Label.new()
	gl.text = Grade.name_for(g)
	gl.add_theme_font_size_override("font_size", 10)
	gl.add_theme_color_override("font_color", Grade.outline_color(g))
	gl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(gl)
	if equipped:
		var el = Label.new()
		el.text = "  —  Equipped"
		el.add_theme_font_size_override("font_size", 10)
		el.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
		el.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(el)
	_tooltip_content.add_child(row)

func _tt_desc(text: String) -> void:
	if text == "":
		return
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 9)
	lbl.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.custom_minimum_size = Vector2(180, 0)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip_content.add_child(lbl)

func _show_item_tooltip(item: Resource, _compare_to: Resource = null) -> void:
	if item == null:
		return
	_clear_tooltip_content()
	var icon = PlayerInventory.item_icons.get(item, null)
	if item is SkillData:
		var s = item as SkillData
		var type_names = ["Melee", "Range", "Mage"]
		var type_str = type_names[s.attack_type_override] if s.attack_type_override < type_names.size() else "?"
		_tt_header(s.display_name + "  [%s]" % type_str, icon, UITheme.TEXT_PRIMARY)
		_tt_grade_subtitle(s)
		_tt_separator()
		var tgt_str = ["Enemy", "Enemy AoE", "Ally", "Self"][s.target_type]
		if s.is_healing():
			_tt_stat_row("Heals", "%d HP" % int(abs(s.eff_damage())), UITheme.TEXT_SUBTLE, UITheme.COLOR_HEAL)
		else:
			_tt_stat_row("Damage", "%d" % int(s.eff_damage()), UITheme.TEXT_SUBTLE, UITheme.COLOR_DAMAGE_NORMAL)
		_tt_stat_row("Range", "%d tiles" % s.range)
		_tt_stat_row("Targets", tgt_str + (" r%d" % s.aoe_radius if s.target_type == SkillData.TargetType.ENEMY_AOE else ""))
		_tt_stat_row("Mana cost", "%d" % s.mana_cost, UITheme.TEXT_SUBTLE, Color(0.55, 0.75, 1.0))
		_tt_desc(s.description)
	elif item is PassiveData:
		var p = item as PassiveData
		_tt_header(p.display_name, icon, UITheme.TEXT_PRIMARY)
		_tt_grade_subtitle(p)
		_tt_separator()
		var triggers = ["On Hit", "On Kill", "Turn Start", "Adjacent Ally", "On Damaged"]
		var effects = ["Stat Buff", "Regen", "Counter", "Dmg Boost"]
		var tname = triggers[p.trigger_event] if p.trigger_event < triggers.size() else "?"
		var ename = effects[p.effect_type] if p.effect_type < effects.size() else "?"
		_tt_stat_row("Trigger", tname)
		_tt_stat_row("Effect", "%s  +%.0f" % [ename, p.eff_value()])
		_tt_desc(p.description)
	elif item is EquipmentData:
		var e = item as EquipmentData
		_tt_header(e.display_name, icon, UITheme.TEXT_PRIMARY)
		_tt_grade_subtitle(e)
		_tt_separator()
		if e.atk_bonus != 0: _tt_stat_row("Damage", "%+d" % e.eff_atk(), UITheme.TEXT_SUBTLE, Color(1.0, 0.75, 0.55))
		if e.def_bonus != 0: _tt_stat_row("Flat damage block", "%+d" % e.eff_def(), UITheme.TEXT_SUBTLE, Color(0.55, 0.85, 1.0))
		if e.block_pct > 0.0:
			var pct = int(e.eff_block_pct() * 100.0)
			var pct_str = "%d%% (capped 30%%)" % pct if pct >= 30 else "%d%%" % pct
			_tt_stat_row("Block %", pct_str, UITheme.TEXT_SUBTLE, Color(0.65, 0.88, 1.0))
		if e.hp_bonus != 0:  _tt_stat_row("Health", "%+d" % e.eff_hp(), UITheme.TEXT_SUBTLE, UITheme.COLOR_HEAL)
		_tt_desc(e.description)
	_tooltip_panel.reset_size()
	_tooltip_panel.modulate.a = 0.0
	_tooltip_panel.visible = true
	_tooltip_visible = true
	var tw = _tooltip_panel.create_tween()
	tw.tween_property(_tooltip_panel, "modulate:a", 1.0, 0.07)

func _show_hero_tooltip(hero: HeroData) -> void:
	_clear_tooltip_content()
	var portrait = Heroes.hero_sprites.get(hero.id, null)
	_tt_header(hero.display_name, portrait, UITheme.TEXT_PRIMARY)
	_tt_separator()

	var saved_hp = PlayerInventory.hero_hp.get(hero.id, -1)
	var cur_hp = hero.base_hp if saved_hp < 0 else saved_hp
	_tt_stat_row("Health", "%d / %d" % [cur_hp, hero.base_hp], UITheme.TEXT_SUBTLE, UITheme.COLOR_HEAL)

	var dmg_min = hero.base_atk
	var dmg_max = int(ceil(hero.base_atk * 1.2))
	_tt_stat_row("Damage", "%d – %d" % [dmg_min, dmg_max], UITheme.TEXT_SUBTLE, Color(1.0, 0.75, 0.55))

	_tt_stat_row("Flat damage block", "%d" % hero.base_def, UITheme.TEXT_SUBTLE, Color(0.55, 0.85, 1.0))

	var saved_mana = PlayerInventory.hero_mana.get(hero.id, -1)
	var cur_mana = 10 if saved_mana < 0 else saved_mana
	_tt_stat_row("Mana", "%d / 10" % cur_mana, UITheme.TEXT_SUBTLE, Color(0.55, 0.75, 1.0))

	if hero.op_buff_name != "":
		_tt_separator()
		var traits_hdr = Label.new()
		traits_hdr.text = "Hero Traits"
		traits_hdr.add_theme_font_size_override("font_size", 10)
		traits_hdr.add_theme_color_override("font_color", UITheme.TEXT_PRIMARY)
		traits_hdr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_tooltip_content.add_child(traits_hdr)
		_tt_stat_row("[%s]" % hero.op_buff_name, hero.op_buff_description, Color(0.62, 0.78, 1.0), UITheme.TEXT_MUTED)

	_tooltip_panel.reset_size()
	_tooltip_panel.modulate.a = 0.0
	_tooltip_panel.visible = true
	_tooltip_visible = true
	var tw = _tooltip_panel.create_tween()
	tw.tween_property(_tooltip_panel, "modulate:a", 1.0, 0.07)

func _hide_tooltip() -> void:
	_tooltip_panel.visible = false
	_tooltip_visible = false

func _position_tooltip(mouse_pos: Vector2) -> void:
	var sz = _tooltip_panel.size
	var vp = get_viewport().get_visible_rect().size
	var pos = mouse_pos + Vector2(14, 14)
	if pos.x + sz.x > vp.x - 4:
		pos.x = mouse_pos.x - sz.x - 8
	if pos.y + sz.y > vp.y - 4:
		pos.y = mouse_pos.y - sz.y - 8
	_tooltip_panel.position = pos

func _connect_item_tooltip(btn: Button, item: Resource) -> void:
	btn.mouse_entered.connect(func(): _show_item_tooltip(item))
	btn.mouse_exited.connect(_hide_tooltip)

func _connect_hero_tooltip(btn: Control, hero: HeroData) -> void:
	btn.mouse_entered.connect(func(): _show_hero_tooltip(hero))
	btn.mouse_exited.connect(_hide_tooltip)

# ── Refresh ───────────────────────────────────────────────────────────────────

func _refresh_all() -> void:
	_rebuild_team_tab()
	_rebuild_loadout_tab()
	_rebuild_forge_tab()
	_update_next_button()
	_update_bottom_forge_controls()

func _rebuild_team_tab() -> void:
	for c in _tab_team.get_children():
		c.queue_free()
	var hbox = HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.add_theme_constant_override("separation", 10)
	_tab_team.add_child(hbox)
	for i in 4:
		hbox.add_child(_make_slot_card(i))

func _make_slot_card(slot_idx: int) -> Control:
	var card = Button.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.focus_mode = Control.FOCUS_NONE
	UITheme.apply_button_theme(card, false, 6)

	var inner = VBoxContainer.new()
	inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	inner.alignment = BoxContainer.ALIGNMENT_CENTER
	inner.add_theme_constant_override("separation", 6)
	card.add_child(inner)

	var id = PlayerInventory.deployed_ids[slot_idx]
	var hero = PlayerInventory.get_hero_by_id(id) if id != &"" else null

	if hero != null:
		var portrait = TextureRect.new()
		portrait.texture = Heroes.hero_sprites.get(hero.id, null)
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.custom_minimum_size = Vector2(64, 64)
		portrait.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(portrait)
		var is_ko = PlayerInventory.hero_ko.get(hero.id, false)
		var name_lbl = Label.new()
		name_lbl.text = hero.display_name + (" [KO]" if is_ko else "")
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.add_theme_font_size_override("font_size", 13)
		name_lbl.add_theme_color_override("font_color",
			UITheme.ENEMY_ACCENT.darkened(0.25) if is_ko else UITheme.TEXT_PRIMARY)
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(name_lbl)
		if hero.op_buff_name != "":
			var buff_lbl = Label.new()
			buff_lbl.text = hero.op_buff_name
			buff_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			buff_lbl.add_theme_font_size_override("font_size", 10)
			buff_lbl.add_theme_color_override("font_color", Color(UITheme.TEXT_SUBTLE.r, UITheme.TEXT_SUBTLE.g, UITheme.TEXT_SUBTLE.b, 0.9))
			buff_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			inner.add_child(buff_lbl)
		_connect_hero_tooltip(card, hero)
	else:
		var slot_lbl = Label.new()
		slot_lbl.text = "Slot %d\n(Empty)" % (slot_idx + 1)
		slot_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot_lbl.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
		slot_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(slot_lbl)

	card.pressed.connect(func(): _open_hero_picker(slot_idx))
	_add_press_punch(card)
	_add_card_tilt(card)
	return card

func _rebuild_loadout_tab() -> void:
	for c in _tab_loadout.get_children():
		c.queue_free()
	var main_vbox = VBoxContainer.new()
	main_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_vbox.add_theme_constant_override("separation", 8)
	_tab_loadout.add_child(main_vbox)
	_slot_selector_row = HBoxContainer.new()
	_slot_selector_row.custom_minimum_size = Vector2(0, 52)
	_slot_selector_row.add_theme_constant_override("separation", 6)
	main_vbox.add_child(_slot_selector_row)
	_loadout_detail = Control.new()
	_loadout_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(_loadout_detail)
	_refresh_slot_selector()

func _refresh_slot_selector() -> void:
	for c in _slot_selector_row.get_children():
		c.queue_free()
	for i in 4:
		var hero_id = PlayerInventory.deployed_ids[i]
		var hero = PlayerInventory.get_hero_by_id(hero_id) if hero_id != &"" else null
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(0, 46)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.focus_mode = Control.FOCUS_NONE
		var portrait = Heroes.hero_sprites.get(hero_id, null) if hero != null else null
		if portrait != null:
			btn.icon = portrait
			btn.expand_icon = true
			btn.add_theme_constant_override("icon_max_width", 28)
			btn.text = "  " + hero.display_name
			var is_ko = PlayerInventory.hero_ko.get(hero_id, false)
			if is_ko:
				btn.modulate = Color(UITheme.ENEMY_ACCENT.r, UITheme.ENEMY_ACCENT.g, UITheme.ENEMY_ACCENT.b, 0.7)
		else:
			btn.text = "Slot %d\n—" % (i + 1)
			btn.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
		UITheme.apply_button_theme(btn, _selected_slot_idx == i)
		if hero != null:
			_connect_hero_tooltip(btn, hero)
		var slot_i = i
		btn.pressed.connect(func(): _select_loadout_slot(slot_i))
		_add_press_punch(btn)
		_add_card_tilt(btn)
		_slot_selector_row.add_child(btn)
	_refresh_loadout_detail()

func _select_loadout_slot(slot_idx: int) -> void:
	_selected_slot_idx = slot_idx
	_refresh_slot_selector()

func _refresh_loadout_detail() -> void:
	for c in _loadout_detail.get_children():
		c.queue_free()
	_loadout_slot_btns.clear()

	var outer = VBoxContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_constant_override("separation", 6)
	_loadout_detail.add_child(outer)

	outer.modulate.a = 0.0
	outer.scale = Vector2(1.0, 0.96)
	var tw = outer.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(outer, "modulate:a", 1.0, 0.16)
	tw.parallel().tween_property(outer, "scale", Vector2(1.0, 1.0), 0.16)

	var hero_id = PlayerInventory.deployed_ids[_selected_slot_idx]
	var hero = PlayerInventory.get_hero_by_id(hero_id) if hero_id != &"" else null

	var slot_header = Label.new()
	slot_header.add_theme_font_size_override("font_size", 15)
	slot_header.add_theme_color_override("font_color", UITheme.TEXT_PRIMARY)
	if hero != null:
		slot_header.text = "SLOT %d  —  %s" % [_selected_slot_idx + 1, hero.display_name.to_upper()]
	else:
		slot_header.text = "SLOT %d  —  EMPTY" % (_selected_slot_idx + 1)
	outer.add_child(slot_header)

	if hero != null and hero.op_buff_name != "":
		var op_lbl = Label.new()
		op_lbl.text = "[%s]  %s" % [hero.op_buff_name, hero.op_buff_description]
		op_lbl.add_theme_font_size_override("font_size", 10)
		op_lbl.add_theme_color_override("font_color", UITheme.TEXT_SUBTLE)
		outer.add_child(op_lbl)

	var cols = HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 10)
	outer.add_child(cols)
	cols.add_child(_make_gear_column(_selected_slot_idx))
	cols.add_child(_make_skills_column(_selected_slot_idx))
	cols.add_child(_make_passives_column(_selected_slot_idx))

# ── Column makers ─────────────────────────────────────────────────────────────

func _col_wrapper(title: String) -> Array:
	var pc = PanelContainer.new()
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pc.add_theme_stylebox_override("panel",
		UITheme.panel_style(Color(UITheme.PANEL_BG.r, UITheme.PANEL_BG.g, UITheme.PANEL_BG.b, 0.92),
			UITheme.PANEL_BORDER, 5, 1))
	var vb = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	pc.add_child(vb)
	var lbl = Label.new()
	lbl.text = title
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", UITheme.TEXT_SUBTLE)
	vb.add_child(lbl)
	vb.add_child(UITheme.menu_separator())
	return [pc, vb]

func _make_gear_column(deploy_slot: int) -> Control:
	var arr = _col_wrapper("Gear")
	arr[1].add_child(_make_item_slot_grid(deploy_slot, "equipment",
			PlayerInventory.slot_equipment_map.get(deploy_slot, [null, null, null, null])))
	return arr[0]

func _make_skills_column(deploy_slot: int) -> Control:
	var arr = _col_wrapper("Skills")
	arr[1].add_child(_make_item_slot_grid(deploy_slot, "skill",
			PlayerInventory.slot_skills_map.get(deploy_slot, [null, null, null, null])))
	return arr[0]

func _make_passives_column(deploy_slot: int) -> Control:
	var arr = _col_wrapper("Passives")
	arr[1].add_child(_make_item_slot_grid(deploy_slot, "passive",
			PlayerInventory.slot_passive_map.get(deploy_slot, [null, null, null, null])))
	return arr[0]

func _make_item_slot_grid(deploy_slot: int, mode: String, slots: Array) -> GridContainer:
	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	for i in 4:
		var item = slots[i] if i < slots.size() else null
		var icon: Texture2D = PlayerInventory.item_icons.get(item, null) if item else null
		var btn = _item_slot_button(item != null, icon, item)
		if item:
			_connect_item_tooltip(btn, item)
		var ds = deploy_slot
		var idx = i
		btn.pressed.connect(func(): _open_item_picker(ds, mode, idx))
		_loadout_slot_btns["%d|%s|%d" % [deploy_slot, mode, i]] = btn
		grid.add_child(btn)
	return grid

func _make_red_x_btn() -> Button:
	var btn = Button.new()
	btn.text = "×"
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(PICKER_ICON_SIZE, PICKER_ICON_SIZE)
	UITheme.apply_button_theme(btn, false, 4)
	btn.add_theme_stylebox_override("normal",
		UITheme.panel_style(Color(UITheme.ENEMY_ACCENT.r * 0.25, 0.04, 0.04, 0.9),
			UITheme.ENEMY_ACCENT.darkened(0.2), 4, 2))
	btn.add_theme_stylebox_override("hover",
		UITheme.panel_style(Color(UITheme.ENEMY_ACCENT.r * 0.45, 0.06, 0.06, 0.95),
			UITheme.ENEMY_ACCENT, 4, 2))
	btn.add_theme_color_override("font_color", UITheme.ENEMY_ACCENT)
	btn.add_theme_color_override("font_hover_color", UITheme.ENEMY_ACCENT.lightened(0.3))
	btn.add_theme_font_size_override("font_size", 22)
	_add_press_punch(btn)
	return btn

func _item_slot_button(filled: bool, icon: Texture2D = null, item: Resource = null) -> Button:
	var btn = Button.new()
	btn.text = ""
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(LOADOUT_SLOT_SIZE, LOADOUT_SLOT_SIZE)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if icon != null:
		btn.icon = icon
		btn.expand_icon = true
		btn.add_theme_constant_override("icon_max_width", LOADOUT_SLOT_SIZE - 4)
	UITheme.apply_button_theme(btn, false, 4)
	if item != null:
		_apply_grade_style(btn, item)
	else:
		btn.add_theme_stylebox_override("normal",
			UITheme.panel_style(UITheme.PANEL_BG_DARK, UITheme.PANEL_BORDER_DARK, 4, 1))
	_add_press_punch(btn)
	_add_card_tilt(btn)
	return btn

# ── Forge tab ─────────────────────────────────────────────────────────────────


func _token_label_text(n: int) -> String:
	match _forge_mode:
		"equipment": return "Gear Tokens:  ⚙ %d" % n
		"skill":     return "Skill Tokens:  ✦ %d" % n
		"passive":   return "Passive Tokens:  ◆ %d" % n
	return ""

func _update_bottom_forge_controls() -> void:
	if _forge_token_lbl == null or _dismantle_all_btn == null:
		return
	var on_forge = _active_tab == 2
	_forge_token_lbl.visible = on_forge
	_dismantle_all_btn.visible = on_forge
	if _undo_btn != null: _undo_btn.visible = on_forge
	if on_forge:
		_displayed_tokens = PlayerInventory.get_tokens(_forge_mode)
		_forge_token_lbl.text = _token_label_text(_displayed_tokens)
		_refresh_undo_btn()

func _rebuild_forge_tab() -> void:
	# Kill all running card tweens before freeing nodes
	for item in _forge_cards:
		_kill_card_tweens(_forge_cards[item])
	_forge_cards.clear()
	_forge_grid = null
	for c in _tab_forge.get_children():
		c.queue_free()
	_dismantle_all_presses = 0
	if _dismantle_all_btn != null:
		_dismantle_all_btn.text = _dismantle_all_label()
	_update_bottom_forge_controls()

	var main_vbox = VBoxContainer.new()
	main_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_vbox.add_theme_constant_override("separation", 8)
	_tab_forge.add_child(main_vbox)

	# Type selector
	var type_row = HBoxContainer.new()
	type_row.custom_minimum_size = Vector2(0, 34)
	type_row.add_theme_constant_override("separation", 6)
	main_vbox.add_child(type_row)
	for m in [["equipment", "Gear"], ["skill", "Skills"], ["passive", "Passives"]]:
		var btn = Button.new()
		btn.text = m[1]
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.focus_mode = Control.FOCUS_NONE
		UITheme.apply_button_theme(btn, _forge_mode == m[0])
		var mode_id = m[0]
		btn.pressed.connect(func(): _select_forge_mode(mode_id))
		_add_press_punch(btn)
		type_row.add_child(btn)

	# Item grid
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main_vbox.add_child(scroll)
	var grid = GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	_forge_grid = grid

	# Equipped first (grade desc), then pool items (grade desc)
	var eq_items: Array = PlayerInventory.get_all_equipped_items(_forge_mode)
	eq_items.sort_custom(func(a, b): return a.grade > b.grade)
	var pool_items: Array = _get_pool(_forge_mode).duplicate()
	pool_items.sort_custom(func(a, b): return a.grade > b.grade)
	var items: Array = eq_items + pool_items

	if items.is_empty():
		var empty = Label.new()
		empty.text = "No items of this type."
		empty.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
		empty.add_theme_font_size_override("font_size", 12)
		grid.add_child(empty)
	else:
		for it in items:
			var card = _make_forge_card(it)
			_forge_cards[it] = card
			grid.add_child(card)

func _make_token_label(name_text: String, count: int) -> Label:
	var lbl = Label.new()
	lbl.text = "%s: %d" % [name_text, count]
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", UITheme.TEXT_PRIMARY)
	return lbl

func _select_forge_mode(mode: String) -> void:
	if mode == _forge_mode:
		return
	_forge_mode = mode
	_rebuild_forge_tab()
	_update_bottom_forge_controls()

func _make_forge_card(item: Resource) -> Control:
	const ICON_SZ = 38
	const BTN_H = 22

	var equipped = not PlayerInventory.find_item_location(_forge_mode, item).is_empty()
	var g = item.grade
	var outline = Grade.outline_color(g)
	var bg = Grade.bg_color(g)

	var pc = PanelContainer.new()
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pc.custom_minimum_size = Vector2(0, 135)
	pc.mouse_filter = Control.MOUSE_FILTER_PASS
	pc.mouse_entered.connect(func(): _show_item_tooltip(item))
	pc.mouse_exited.connect(_hide_tooltip)
	var card_sb = UITheme.panel_style(bg, outline, 5, 2)
	card_sb.content_margin_left   = 8.0
	card_sb.content_margin_right  = 8.0
	card_sb.content_margin_top    = 8.0
	card_sb.content_margin_bottom = 8.0
	if equipped:
		card_sb.bg_color = Color(bg.r, bg.g, bg.b, 0.25)
	pc.add_theme_stylebox_override("panel", card_sb)
	var _tween_list: Array = []
	pc.set_meta("item", item)
	pc.set_meta("card_sb", card_sb)
	pc.set_meta("tween_list", _tween_list)

	var outer_vb = VBoxContainer.new()
	outer_vb.add_theme_constant_override("separation", 14)
	pc.add_child(outer_vb)

	# Content area: vertically centered, expands to fill space above the buttons
	var content_vb = VBoxContainer.new()
	content_vb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_vb.alignment = BoxContainer.ALIGNMENT_CENTER
	outer_vb.add_child(content_vb)

	# Icon fills available vertical space, resizes proportionally
	var icon_rect = TextureRect.new()
	icon_rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	icon_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon = PlayerInventory.item_icons.get(item, null)
	if icon != null:
		icon_rect.texture = icon
	content_vb.add_child(icon_rect)

	# Name + grade below the icon, centered
	var name_lbl = Label.new()
	name_lbl.text = item.display_name
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color", UITheme.TEXT_PRIMARY)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_lbl.clip_text = true
	content_vb.add_child(name_lbl)

	var grade_lbl = Label.new()
	grade_lbl.text = Grade.name_for(g)
	grade_lbl.add_theme_font_size_override("font_size", 10)
	grade_lbl.add_theme_color_override("font_color", outline)
	grade_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	grade_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_vb.add_child(grade_lbl)
	pc.set_meta("grade_lbl", grade_lbl)

	# Row 2: + and x / Equipped
	var btn_row = HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 4)
	btn_row.custom_minimum_size = Vector2(0, BTN_H)
	outer_vb.add_child(btn_row)

	var up_btn = Button.new()
	up_btn.focus_mode = Control.FOCUS_NONE
	up_btn.text = "+"
	up_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	up_btn.custom_minimum_size = Vector2(0, BTN_H)
	UITheme.apply_button_theme(up_btn, false, 3)
	var can_up_now = PlayerInventory.get_tokens(_forge_mode) >= Grade.upgrade_cost(g)
	if not can_up_now:
		up_btn.modulate = Color(0.45, 0.45, 0.45)
	elif equipped:
		up_btn.modulate = Color(0.55, 1.0, 0.60)
	_add_press_punch(up_btn)
	up_btn.pressed.connect(func():
		if PlayerInventory.get_tokens(_forge_mode) < Grade.upgrade_cost(item.grade):
			Utils.floating_text("Not enough tokens", UITheme.ENEMY_ACCENT,
				get_viewport().get_mouse_position(), _tab_forge, 11)
			return
		_on_forge_upgrade(item)
	)
	up_btn.mouse_entered.connect(func():
		var _c = Grade.upgrade_cost(item.grade)
		_show_forge_btn_tip("Upgrade: costs %d token%s" % [_c, "s" if _c != 1 else ""],
			UITheme.TEXT_PRIMARY))
	up_btn.mouse_exited.connect(_hide_tooltip)
	btn_row.add_child(up_btn)
	pc.set_meta("up_btn", up_btn)

	if equipped:
		var eq_lbl = Label.new()
		eq_lbl.text = "Equipped"
		eq_lbl.add_theme_font_size_override("font_size", 8)
		eq_lbl.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
		eq_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		eq_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		eq_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		eq_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		btn_row.add_child(eq_lbl)
	else:
		var dis_btn = Button.new()
		dis_btn.focus_mode = Control.FOCUS_NONE
		dis_btn.text = "x"
		dis_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		dis_btn.custom_minimum_size = Vector2(0, BTN_H)
		UITheme.apply_button_theme(dis_btn, false, 3)
		dis_btn.add_theme_color_override("font_color", UITheme.ENEMY_ACCENT)
		_add_press_punch(dis_btn)
		dis_btn.pressed.connect(func(): _on_forge_dismantle(item))
		dis_btn.mouse_entered.connect(func():
			var _y = Grade.dismantle_yield(item.grade)
			_show_forge_btn_tip(
				"Dismantle: yields +%d token%s" % [_y, "s" if _y != 1 else ""],
				UITheme.ENEMY_ACCENT,
				"Returns 100% of tokens invested in the item"))
		dis_btn.mouse_exited.connect(_hide_tooltip)
		btn_row.add_child(dis_btn)

	if Grade.is_animated(g):
		_animate_card_full(card_sb, grade_lbl, g, pc, _tween_list)

	return pc

func _forge_stat_preview(item: Resource) -> String:
	var g = item.grade
	var ng = g + 1
	var parts: Array = []
	if item is EquipmentData:
		var e = item as EquipmentData
		if e.atk_bonus != 0:
			parts.append("ATK %+d→%+d" % [e.atk_bonus * Grade.stat_mult(g), e.atk_bonus * Grade.stat_mult(ng)])
		if e.def_bonus != 0:
			parts.append("DEF %+d→%+d" % [e.def_bonus * Grade.stat_mult(g), e.def_bonus * Grade.stat_mult(ng)])
		if e.hp_bonus != 0:
			parts.append("HP %+d→%+d" % [e.hp_bonus * Grade.stat_mult(g), e.hp_bonus * Grade.stat_mult(ng)])
		if e.block_pct > 0.0:
			parts.append("Block %d%%→%d%%" % [g, ng])
	elif item is SkillData:
		var s = item as SkillData
		var base = int(abs(s.base_damage))
		var verb = "Heal" if s.is_healing() else "DMG"
		parts.append("%s %d→%d" % [verb, base * Grade.stat_mult(g), base * Grade.stat_mult(ng)])
	elif item is PassiveData:
		var p = item as PassiveData
		parts.append("Effect %.0f→%.0f" % [p.effect_value * Grade.stat_mult(g), p.effect_value * Grade.stat_mult(ng)])
	return "   ".join(parts)

func _forge_stat_preview_short(item: Resource) -> String:
	var g = item.grade
	var ng = g + 1
	if item is EquipmentData:
		var e = item as EquipmentData
		if e.atk_bonus != 0: return "ATK %d→%d" % [e.atk_bonus * Grade.stat_mult(g), e.atk_bonus * Grade.stat_mult(ng)]
		if e.def_bonus != 0: return "DEF %d→%d" % [e.def_bonus * Grade.stat_mult(g), e.def_bonus * Grade.stat_mult(ng)]
		if e.hp_bonus != 0:  return "HP %d→%d" % [e.hp_bonus * Grade.stat_mult(g), e.hp_bonus * Grade.stat_mult(ng)]
		if e.block_pct > 0.0: return "Block %d%%→%d%%" % [g, ng]
	elif item is SkillData:
		var s = item as SkillData
		var base = int(abs(s.base_damage))
		var verb = "Heal" if s.is_healing() else "DMG"
		return "%s %d→%d" % [verb, base * Grade.stat_mult(g), base * Grade.stat_mult(ng)]
	elif item is PassiveData:
		var p = item as PassiveData
		return "%.0f→%.0f" % [p.effect_value * Grade.stat_mult(g), p.effect_value * Grade.stat_mult(ng)]
	return ""

func _kill_card_tweens(pc: PanelContainer) -> void:
	if not is_instance_valid(pc): return
	var tl: Array = pc.get_meta("tween_list", [])
	for tw in tl:
		if tw is Tween and tw.is_valid(): tw.kill()
	tl.clear()

func _refresh_forge_card_visual(item: Resource) -> void:
	var pc = _forge_cards.get(item) as PanelContainer
	if not is_instance_valid(pc): return
	_kill_card_tweens(pc)
	var g = item.grade
	var outline = Grade.outline_color(g)
	var bg = Grade.bg_color(g)
	var card_sb = pc.get_meta("card_sb") as StyleBoxFlat
	var grade_lbl = pc.get_meta("grade_lbl") as Label
	var up_btn = pc.get_meta("up_btn") as Button
	var tl: Array = pc.get_meta("tween_list")
	card_sb.border_color = outline
	card_sb.bg_color = bg
	grade_lbl.text = Grade.name_for(g)
	grade_lbl.add_theme_color_override("font_color", outline)
	var can_up = PlayerInventory.get_tokens(_forge_mode) >= Grade.upgrade_cost(g)
	var eq = not PlayerInventory.find_item_location(_forge_mode, item).is_empty()
	up_btn.modulate = Color(0.45, 0.45, 0.45) if not can_up else (Color(0.55, 1.0, 0.60) if eq else Color.WHITE)
	if Grade.is_animated(g):
		_animate_card_full(card_sb, grade_lbl, g, pc, tl)

func _refresh_all_upgrade_btn_modulates() -> void:
	for it in _forge_cards:
		var pc = _forge_cards[it] as PanelContainer
		if not is_instance_valid(pc): continue
		var up_btn = pc.get_meta("up_btn", null) as Button
		if up_btn == null or not is_instance_valid(up_btn): continue
		var can_up = PlayerInventory.get_tokens(_forge_mode) >= Grade.upgrade_cost(it.grade)
		var eq = not PlayerInventory.find_item_location(_forge_mode, it).is_empty()
		up_btn.modulate = Color(0.45, 0.45, 0.45) if not can_up else (Color(0.55, 1.0, 0.60) if eq else Color.WHITE)

# Animate a set of cards from recorded old global positions to wherever they now sit.
# Each card gets a random 0-8 frame delay so they don't all start at once.
func _animate_cards_from(old_positions: Dictionary) -> void:
	await get_tree().process_frame
	for card in old_positions:
		if not is_instance_valid(card): continue
		var delta = old_positions[card] - card.global_position
		if delta.length() < 2.0: continue
		card.position += delta
		var tw = card.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(card, "position", card.position - delta, 0.28)

func _resort_forge_cards() -> void:
	if _forge_grid == null: return
	var cards: Array = []
	for child in _forge_grid.get_children():
		if child.has_meta("item"): cards.append(child)

	var old_pos: Dictionary = {}
	for card in cards: old_pos[card] = card.global_position

	cards.sort_custom(func(a, b):
		var ia = a.get_meta("item"); var ib = b.get_meta("item")
		var a_eq = not PlayerInventory.find_item_location(_forge_mode, ia).is_empty()
		var b_eq = not PlayerInventory.find_item_location(_forge_mode, ib).is_empty()
		if a_eq != b_eq: return a_eq
		return ia.grade > ib.grade
	)
	for i in cards.size(): _forge_grid.move_child(cards[i], i)
	_animate_cards_from(old_pos)

func _on_forge_upgrade(item: Resource) -> void:
	var old_grade = item.grade
	if PlayerInventory.upgrade_item(_forge_mode, item):
		# Clear undo to prevent negative-balance exploit
		_undo_item = null; _undo_mode = ""; _undo_yield = 0; _undo_icon = null
		_refresh_undo_btn()
		var pc = _forge_cards.get(item) as PanelContainer
		_refresh_forge_card_visual(item)
		if is_instance_valid(pc):
			_flash_upgrade_card(pc, item.grade)
			_maybe_show_tier_cross(pc, old_grade, item.grade)
		_resort_forge_cards()
		_refresh_all_upgrade_btn_modulates()
		_displayed_tokens = PlayerInventory.get_tokens(_forge_mode)
		_update_bottom_forge_controls()
		_shake_panel(4.0)

func _on_forge_dismantle(item: Resource) -> void:
	var pc = _forge_cards.get(item) as PanelContainer
	var card_center = Vector2.ZERO
	var item_color = Grade.outline_color(item.grade)
	var item_yield = Grade.dismantle_yield(item.grade)
	var icon_snapshot = PlayerInventory.item_icons.get(item, null)  # capture before erase
	if is_instance_valid(pc):
		card_center = pc.global_position + pc.size / 2

	var old_positions: Dictionary = {}
	if _forge_grid != null:
		for child in _forge_grid.get_children():
			if child.has_meta("item") and child != pc:
				old_positions[child] = child.global_position

	if PlayerInventory.dismantle_item(_forge_mode, item):
		# Store undo state (overwrites any previous)
		_undo_item = item
		_undo_mode = _forge_mode
		_undo_yield = item_yield
		_undo_icon = icon_snapshot
		_refresh_undo_btn()

		Utils.floating_text("+%d" % item_yield, item_color, card_center, _root_ctrl, 13)
		_displayed_tokens = PlayerInventory.get_tokens(_forge_mode) - item_yield
		_spawn_token_dots(card_center, item_yield, item_color)
		_kill_card_tweens(pc)
		if is_instance_valid(pc): pc.queue_free()
		_forge_cards.erase(item)
		_animate_cards_from(old_positions)
		_refresh_all_upgrade_btn_modulates()
		_shake_panel(3.0)

func _dismantle_all_label() -> String:
	match _dismantle_all_presses:
		0: return "Dismantle All Unequipped"
		1: return "Are you sure?"
		2: return "Are you really really sure?"
	return "Dismantle All Unequipped"

func _on_dismantle_all_pressed(btn: Button) -> void:
	_dismantle_all_presses += 1
	if _dismantle_all_presses >= 3:
		var pool_items = _get_pool(_forge_mode).duplicate()
		var btn_center = _dismantle_all_btn.global_position + _dismantle_all_btn.size / 2
		_displayed_tokens = PlayerInventory.get_tokens(_forge_mode)
		PlayerInventory.dismantle_all_unequipped(_forge_mode)
		for it in pool_items:
			var pc = _forge_cards.get(it) as PanelContainer
			var card_center = btn_center
			if is_instance_valid(pc): card_center = pc.global_position + pc.size / 2
			var it_yield = Grade.dismantle_yield(it.grade)
			_spawn_token_dots(card_center, it_yield, Grade.outline_color(it.grade))
			_kill_card_tweens(pc)
			if is_instance_valid(pc): pc.queue_free()
			_forge_cards.erase(it)
		_dismantle_all_presses = 0
		btn.text = _dismantle_all_label()
		_refresh_all_upgrade_btn_modulates()
		_shake_panel(6.0)
	else:
		btn.text = _dismantle_all_label()

func _show_forge_btn_tip(msg: String, color: Color, subtext: String = "") -> void:
	_clear_tooltip_content()
	var lbl = Label.new()
	lbl.text = msg
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", color)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip_content.add_child(lbl)
	if subtext != "":
		var sub = Label.new()
		sub.text = subtext
		sub.add_theme_font_size_override("font_size", 9)
		sub.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
		sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_tooltip_content.add_child(sub)
	_tooltip_panel.reset_size()
	_tooltip_panel.modulate.a = 0.0
	_tooltip_panel.visible = true
	_tooltip_visible = true
	var tw = _tooltip_panel.create_tween()
	tw.tween_property(_tooltip_panel, "modulate:a", 1.0, 0.07)

func _float_forge_text(msg: String) -> void:
	Utils.floating_text(msg, UITheme.ENEMY_ACCENT, get_viewport().get_mouse_position(), _tab_forge, 13)

func _refresh_undo_btn() -> void:
	if _undo_btn == null: return
	if _undo_item != null and _undo_icon != null:
		_undo_btn.text = ""
		_undo_btn.icon = _undo_icon
		_undo_btn.expand_icon = true
		_undo_btn.add_theme_constant_override("icon_max_width", 32)
		_undo_btn.modulate = Color.WHITE
	else:
		_undo_btn.text = "↩"
		_undo_btn.icon = null
		_undo_btn.modulate = Color(0.6, 0.6, 0.6)

func _on_undo_pressed() -> void:
	if _undo_item == null: return
	# Restore icon before returning to pool
	if _undo_icon != null:
		PlayerInventory.item_icons[_undo_item] = _undo_icon
	# Return item to the correct pool
	match _undo_mode:
		"equipment": PlayerInventory.item_pool_equipment.append(_undo_item)
		"skill":     PlayerInventory.item_pool_skills.append(_undo_item)
		"passive":   PlayerInventory.item_pool_passives.append(_undo_item)
	# Deduct the tokens that were gained from the dismantle
	match _undo_mode:
		"equipment": PlayerInventory.gear_tokens    = maxi(0, PlayerInventory.gear_tokens    - _undo_yield)
		"skill":     PlayerInventory.skill_tokens   = maxi(0, PlayerInventory.skill_tokens   - _undo_yield)
		"passive":   PlayerInventory.passive_tokens = maxi(0, PlayerInventory.passive_tokens - _undo_yield)
	# Clear undo state
	_undo_item = null
	_undo_mode = ""
	_undo_yield = 0
	_undo_icon = null
	# Rebuild the forge tab so the item card reappears
	if _forge_mode == _undo_mode or _undo_mode == "":
		_rebuild_forge_tab()
	else:
		_rebuild_forge_tab()  # always rebuild since the pool changed
	_update_bottom_forge_controls()

func _show_dismantle_all_tip() -> void:
	var pool = _get_pool(_forge_mode)
	if pool.is_empty():
		_show_forge_btn_tip("Nothing to dismantle", UITheme.TEXT_MUTED)
		return
	var total = 0
	for it in pool:
		total += Grade.dismantle_yield(it.grade)
	var sym = {"equipment": "⚙", "skill": "✦", "passive": "◆"}.get(_forge_mode, "")
	_show_forge_btn_tip("Dismantle all: yields +%d %s" % [total, sym], UITheme.ENEMY_ACCENT)

# Panel shake — tweens _panel.position back and forth.
func _shake_panel(strength: float = 5.0) -> void:
	var base = Vector2(PANEL_X, PANEL_Y)
	var tw = _panel.create_tween().set_trans(Tween.TRANS_SINE)
	for i in 5:
		tw.tween_property(_panel, "position",
			base + Vector2(randf_range(-strength, strength), randf_range(-strength, strength)), 0.035)
	tw.tween_property(_panel, "position", base, 0.04)

# Flash a card's border white then back to its grade color, + punch.
func _flash_upgrade_card(pc: PanelContainer, grade: int) -> void:
	_punch_control(pc, 1.10, 0.08, 0.14)
	var card_sb = pc.get_meta("card_sb", null) as StyleBoxFlat
	if card_sb == null: return
	var target_color = Grade.outline_color(grade)
	var tw = pc.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(card_sb, "border_color", Color.WHITE, 0.06)
	tw.tween_property(card_sb, "border_color", target_color, 0.35)

# Show a floating tier name if the upgrade just crossed into a new named grade.
func _maybe_show_tier_cross(pc: PanelContainer, old_grade: int, new_grade: int) -> void:
	if old_grade >= 19 or new_grade > 19: return  # Infinite+ not a new tier event
	if Grade.name_for(old_grade) != Grade.name_for(new_grade):
		Utils.floating_text("✦ " + Grade.name_for(new_grade),
			Grade.outline_color(new_grade), pc.global_position + pc.size / 2, _root_ctrl, 14)

# Spawn N arc-shaped dots from source_global to the token label.
# Each dot increments the displayed token counter when it arrives.
# Spawn dots that burst in a random direction then home to the token label.
# Uses cubic bezier: P0=source, P1=source+burst, P2=target+approach, P3=target.
func _spawn_token_dots(source_global: Vector2, yield_n: int, color: Color) -> void:
	if yield_n <= 0 or _forge_token_lbl == null or _root_ctrl == null: return
	var dot_count = clampi(yield_n, 1, 9)
	var tokens_per_dot = yield_n / dot_count
	var remainder = yield_n - tokens_per_dot * dot_count
	var target_global = _forge_token_lbl.global_position + _forge_token_lbl.size / 2

	for i in dot_count:
		var carry = tokens_per_dot + (1 if i < remainder else 0)
		var dot = ColorRect.new()
		dot.size = Vector2(8, 8)
		dot.color = color
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root_ctrl.add_child(dot)
		dot.position = source_global - Vector2(4, 4)

		# Random burst direction and distance for P1
		var burst_angle = randf() * TAU
		var burst_dist = randf_range(40, 120)
		var p1 = source_global + Vector2(cos(burst_angle), sin(burst_angle)) * burst_dist
		# P2 slightly before target so it homes in smoothly
		var approach = (source_global - target_global).normalized() * randf_range(20, 50)
		var p2 = target_global + approach

		var delay = i * 0.07
		var dur = randf_range(0.7, 1.1)  # half speed (doubled duration)

		var tw = dot.create_tween()
		if delay > 0: tw.tween_interval(delay)
		var carried = carry
		tw.tween_method(func(t: float):
			# Cubic bezier: source → p1 → p2 → target
			var u = 1.0 - t
			var p = source_global*(u*u*u) + p1*(3*u*u*t) + p2*(3*u*t*t) + target_global*(t*t*t)
			if is_instance_valid(dot): dot.position = p - Vector2(4, 4)
		, 0.0, 1.0, dur)
		tw.finished.connect(func():
			if not is_instance_valid(dot): return
			dot.queue_free()
			_displayed_tokens += carried
			if is_instance_valid(_forge_token_lbl):
				_forge_token_lbl.text = _token_label_text(_displayed_tokens)
				_punch_control(_forge_token_lbl, 1.12, 0.05, 0.08)
		)

func _apply_grade_style(btn: Button, item: Resource) -> void:
	var g: int = item.grade
	var outline = Grade.outline_color(g)
	var bg = Grade.bg_color(g)
	var sb = UITheme.panel_style(bg, outline, 4, 2)
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", UITheme.panel_style(bg.lightened(0.08), outline, 4, 2))
	btn.add_theme_stylebox_override("pressed", UITheme.panel_style(bg, outline, 4, 2))
	btn.add_theme_stylebox_override("focus", UITheme.panel_style(bg, outline, 4, 2))
	if Grade.is_animated(g):
		_animate_border_only(sb, g, btn)

func _animate_grade_border(btn: Button, grade: int) -> void:
	if not btn.is_inside_tree():
		btn.tree_entered.connect(func(): _animate_grade_border(btn, grade), CONNECT_ONE_SHOT)
		return
	var sb = btn.get_theme_stylebox("normal") as StyleBoxFlat
	if sb == null:
		return
	_animate_border_only(sb, grade, btn)

# Returns [color_a, color_b, step_duration] for two-color grades.
static func _grade_anim_pair(grade: int) -> Array:
	if grade >= 16: return [Color(0.45, 0.08, 0.72), Color(0.18, 0.04, 0.42), 3.0]
	elif grade == 15: return [Color(1.0, 1.0, 0.88),   Color(1.0, 0.75, 0.18),  2.5]
	elif grade == 14: return [Color(0.0, 1.0, 0.90),   Color(0.08, 0.55, 0.62), 2.8]
	elif grade == 13: return [Color(1.0, 0.55, 0.95),  Color(0.70, 0.08, 0.58), 2.8]
	elif grade == 12: return [Color(0.55, 0.35, 1.0),  Color(0.18, 0.08, 0.52), 3.0]
	elif grade == 11: return [Color(1.0, 0.90, 0.35),  Color(0.78, 0.52, 0.05), 3.0]
	else:             return [Color(1.0, 0.68, 0.18),  Color(0.72, 0.30, 0.04), 3.2]

func _start_two_color_sb_anim(sb: StyleBoxFlat, prop: String,
		ca: Color, cb: Color, spd: float, owner_node: Node, tl: Array = []) -> void:
	var t = randf()
	sb.set(prop, ca.lerp(cb, t))
	var warmup = owner_node.create_tween()
	tl.append(warmup)
	warmup.tween_property(sb, prop, cb, maxf(0.05, spd * (1.0 - t)))
	warmup.finished.connect(func():
		if not is_instance_valid(owner_node): return
		var lp = owner_node.create_tween().set_loops()
		tl.append(lp)
		lp.tween_property(sb, prop, ca, spd)
		lp.tween_property(sb, prop, cb, spd)
	)

func _start_two_color_label_anim(lbl: Label, ca: Color, cb: Color,
		spd: float, owner_node: Node, tl: Array = []) -> void:
	var t = randf()
	var init = ca.lerp(cb, t)
	lbl.add_theme_color_override("font_color", init)
	var warmup = owner_node.create_tween()
	tl.append(warmup)
	warmup.tween_method(func(c: Color): lbl.add_theme_color_override("font_color", c),
		init, cb, maxf(0.05, spd * (1.0 - t)))
	warmup.finished.connect(func():
		if not is_instance_valid(owner_node): return
		var lp = owner_node.create_tween().set_loops()
		tl.append(lp)
		lp.tween_method(func(c: Color): lbl.add_theme_color_override("font_color", c), cb, ca, spd)
		lp.tween_method(func(c: Color): lbl.add_theme_color_override("font_color", c), ca, cb, spd)
	)

func _animate_border_only(sb: StyleBoxFlat, grade: int, owner_node: Node) -> void:
	if not owner_node.is_inside_tree():
		owner_node.tree_entered.connect(
			func(): _animate_border_only(sb, grade, owner_node), CONNECT_ONE_SHOT)
		return
	if grade >= 19:
		var hues = [0.0, 0.14, 0.28, 0.42, 0.57, 0.71, 0.85]
		var offset = randi() % hues.size()
		var tw = owner_node.create_tween().set_loops()
		for i in hues.size():
			tw.tween_property(sb, "border_color",
				Color.from_hsv(hues[(i + offset) % hues.size()], 0.9, 1.0), 1.8)
	else:
		var pair = _grade_anim_pair(grade)
		_start_two_color_sb_anim(sb, "border_color", pair[0], pair[1], pair[2], owner_node)

# Full 3-layer animation for forge cards.
# Border fastest (×1.0), grade label medium (×1.18), background slowest (×1.42).
# Each layer starts at an independent random phase.
func _animate_card_full(card_sb: StyleBoxFlat, grade_lbl: Label,
		grade: int, owner_node: Node, tl: Array = []) -> void:
	if not owner_node.is_inside_tree():
		owner_node.tree_entered.connect(
			func(): _animate_card_full(card_sb, grade_lbl, grade, owner_node, tl), CONNECT_ONE_SHOT)
		return

	if grade >= 19:
		var hues = [0.0, 0.14, 0.28, 0.42, 0.57, 0.71, 0.85]
		var step = 2.0
		var b_tw = owner_node.create_tween().set_loops()
		var g_tw = owner_node.create_tween().set_loops()
		var l_tw = owner_node.create_tween().set_loops()
		tl.append(b_tw); tl.append(g_tw); tl.append(l_tw)
		for i in hues.size():
			var h = hues[i]; var hn = hues[(i + 1) % hues.size()]
			b_tw.tween_property(card_sb, "border_color", Color.from_hsv(h, 0.92, 1.0), step)
			g_tw.tween_property(card_sb, "bg_color", Color.from_hsv(h, 0.88, 0.32), step)
			l_tw.tween_method(func(c: Color): grade_lbl.add_theme_color_override("font_color", c),
				Color.from_hsv(h, 0.78, 1.0), Color.from_hsv(hn, 0.78, 1.0), step)
		return

	var pair = _grade_anim_pair(grade)
	var ca: Color = pair[0]; var cb: Color = pair[1]; var spd: float = pair[2]
	var bg_a = Color(ca.r * 0.28, ca.g * 0.28, ca.b * 0.28)
	var bg_b = Color(cb.r * 0.28, cb.g * 0.28, cb.b * 0.28)
	_start_two_color_sb_anim(card_sb, "border_color", ca, cb, spd * 1.0,   owner_node, tl)
	_start_two_color_label_anim(grade_lbl, ca.lightened(0.30), cb.lightened(0.22), spd * 1.18, owner_node, tl)
	_start_two_color_sb_anim(card_sb, "bg_color", bg_a, bg_b, spd * 1.42, owner_node, tl)

# ── Picker logic ──────────────────────────────────────────────────────────────

func _open_hero_picker(slot_idx: int) -> void:
	_picker_mode = "hero"
	_picker_item_slot = slot_idx
	_picker_deploy_slot = -1
	_picker_title_lbl.text = "Choose Hero  —  Slot %d" % (slot_idx + 1)
	_picker_grid.columns = 5
	for c in _picker_grid.get_children():
		c.queue_free()

	var occupied_id = PlayerInventory.deployed_ids[slot_idx]
	if occupied_id != &"":
		var remove_btn = _make_red_x_btn()
		remove_btn.pressed.connect(func(): _on_hero_remove(slot_idx))
		_picker_grid.add_child(remove_btn)

	for hero in PlayerInventory.owned_heroes:
		var is_ko = PlayerInventory.hero_ko.get(hero.id, false)
		var is_deployed = PlayerInventory.deployed_ids.has(hero.id)
		var btn = Button.new()
		btn.text = ""
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(PICKER_ICON_SIZE, PICKER_ICON_SIZE)
		var hero_sprite = Heroes.hero_sprites.get(hero.id, null)
		if hero_sprite != null:
			btn.icon = hero_sprite
			btn.expand_icon = true
			btn.add_theme_constant_override("icon_max_width", PICKER_ICON_SIZE - 4)
		_connect_hero_tooltip(btn, hero)
		if is_ko:
			btn.modulate = Color(UITheme.ENEMY_ACCENT.r, UITheme.ENEMY_ACCENT.g, UITheme.ENEMY_ACCENT.b, 0.75)
			btn.disabled = true
		UITheme.apply_button_theme(btn, is_deployed)
		if is_deployed:
			btn.add_theme_stylebox_override("normal",
				UITheme.panel_style(UITheme.BTN_BG, UITheme.HERO_ACCENT, 4, 2))
		var hid = hero.id
		btn.pressed.connect(func(): _on_hero_pick(hid, slot_idx))
		_add_press_punch(btn)
		_add_card_tilt(btn)
		_picker_grid.add_child(btn)

	_show_picker_animated()

func _open_item_picker(deploy_slot: int, mode: String, item_slot: int) -> void:
	_picker_mode = mode
	_picker_item_slot = item_slot
	_picker_deploy_slot = deploy_slot
	var title_map = {"skill": "Choose Skill", "passive": "Choose Passive", "equipment": "Choose Gear"}
	_picker_title_lbl.text = "%s  —  Slot %d  /  Item %d" % [title_map.get(mode, "Choose Item"), deploy_slot + 1, item_slot + 1]
	_picker_grid.columns = 5
	for c in _picker_grid.get_children():
		c.queue_free()

	var current_item = _get_slot_item(deploy_slot, mode, item_slot)

	var unequip_btn = _make_red_x_btn()
	unequip_btn.pressed.connect(func(): _on_unequip(deploy_slot, mode, item_slot))
	_picker_grid.add_child(unequip_btn)

	# Current item always appears first (highlighted)
	if current_item != null:
		var btn = _make_picker_icon_btn(current_item, true)
		var itm = current_item
		btn.pressed.connect(func(): _on_item_pick(itm))
		btn.mouse_entered.connect(func(): _show_item_tooltip(current_item))
		btn.mouse_exited.connect(_hide_tooltip)
		_picker_grid.add_child(btn)

	# Collect remaining items: equipped-in-other-slots first (grade desc), then pool (grade desc)
	var elsewhere: Array = []
	for it in PlayerInventory.get_all_equipped_items(mode):
		if it != current_item:
			elsewhere.append(it)
	elsewhere.sort_custom(func(a, b): return a.grade > b.grade)

	var pool_sorted: Array = _get_pool(mode).duplicate()
	pool_sorted.sort_custom(func(a, b): return a.grade > b.grade)

	for item in elsewhere:
		var btn = _make_picker_icon_btn(item, false, true)
		var itm = item
		btn.pressed.connect(func(): _on_item_swap_pick(itm))
		btn.mouse_entered.connect(func(): _show_item_tooltip(item, current_item))
		btn.mouse_exited.connect(_hide_tooltip)
		_picker_grid.add_child(btn)

	for item in pool_sorted:
		var btn = _make_picker_icon_btn(item, false)
		var itm = item
		btn.pressed.connect(func(): _on_item_pick(itm))
		btn.mouse_entered.connect(func(): _show_item_tooltip(item, current_item))
		btn.mouse_exited.connect(_hide_tooltip)
		_picker_grid.add_child(btn)

	_show_picker_animated()

func _make_picker_icon_btn(item: Resource, is_current: bool, is_elsewhere: bool = false) -> Button:
	var btn = Button.new()
	btn.text = ""
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(PICKER_ICON_SIZE, PICKER_ICON_SIZE)
	var icon = PlayerInventory.item_icons.get(item, null)
	if icon != null:
		btn.icon = icon
		btn.expand_icon = true
		btn.add_theme_constant_override("icon_max_width", PICKER_ICON_SIZE - 4)
	if is_current:
		UITheme.apply_button_theme(btn, true, 4)
		btn.add_theme_stylebox_override("normal",
			UITheme.panel_style(UITheme.BTN_BG_HOVER, UITheme.HERO_ACCENT, 4, 2))
	elif is_elsewhere:
		UITheme.apply_button_theme(btn, false, 4)
		var _el_outline = Grade.outline_color(item.grade)
		btn.add_theme_stylebox_override("normal",
			UITheme.panel_style(Color(0, 0, 0, 0), _el_outline, 4, 2))
		btn.add_theme_stylebox_override("hover",
			UITheme.panel_style(Color(_el_outline.r, _el_outline.g, _el_outline.b, 0.15), _el_outline, 4, 2))
	else:
		UITheme.apply_button_theme(btn, false, 4)
		_apply_grade_style(btn, item)
	_add_press_punch(btn)
	_add_card_tilt(btn)
	return btn

func _on_item_swap_pick(item: Resource) -> void:
	PlayerInventory.move_item_to_slot(_picker_deploy_slot, _picker_mode, _picker_item_slot, item)
	_close_picker()
	_refresh_loadout_detail()
	_flash_slot(_picker_deploy_slot, _picker_mode, _picker_item_slot)

func _get_slot_item(deploy_slot: int, mode: String, item_slot: int):
	match mode:
		"skill":
			var slots = PlayerInventory.slot_skills_map.get(deploy_slot, [])
			return slots[item_slot] if item_slot < slots.size() else null
		"passive":
			var slots = PlayerInventory.slot_passive_map.get(deploy_slot, [])
			return slots[item_slot] if item_slot < slots.size() else null
		"equipment":
			var slots = PlayerInventory.slot_equipment_map.get(deploy_slot, [])
			return slots[item_slot] if item_slot < slots.size() else null
	return null

func _get_pool(mode: String) -> Array:
	match mode:
		"skill": return PlayerInventory.item_pool_skills
		"passive": return PlayerInventory.item_pool_passives
		"equipment": return PlayerInventory.item_pool_equipment
	return []

func _close_picker() -> void:
	_picker_overlay.visible = false
	_hide_tooltip()

func _on_hero_remove(slot_idx: int) -> void:
	PlayerInventory.clear_slot(slot_idx)
	_close_picker()
	_rebuild_team_tab()
	_update_next_button()

func _on_hero_pick(hero_id: StringName, slot_idx: int) -> void:
	PlayerInventory.set_slot(slot_idx, hero_id)
	_close_picker()
	_rebuild_team_tab()
	_update_next_button()

func _on_item_pick(item: Resource) -> void:
	match _picker_mode:
		"skill":
			PlayerInventory.equip_skill(_picker_deploy_slot, _picker_item_slot, item as SkillData)
		"passive":
			PlayerInventory.equip_passive(_picker_deploy_slot, _picker_item_slot, item as PassiveData)
		"equipment":
			PlayerInventory.equip_equipment(_picker_deploy_slot, _picker_item_slot, item as EquipmentData)
	_close_picker()
	_refresh_loadout_detail()
	_flash_slot(_picker_deploy_slot, _picker_mode, _picker_item_slot)

func _on_unequip(deploy_slot: int, mode: String, item_slot: int) -> void:
	match mode:
		"skill":
			PlayerInventory.unequip_skill(deploy_slot, item_slot)
		"passive":
			PlayerInventory.unequip_passive(deploy_slot, item_slot)
		"equipment":
			PlayerInventory.unequip_equipment(deploy_slot, item_slot)
	_close_picker()
	_refresh_loadout_detail()
	_flash_slot(deploy_slot, mode, item_slot)

# ── Tab / button state ────────────────────────────────────────────────────────

func _switch_tab(idx: int) -> void:
	if idx == _active_tab:
		return
	match idx:
		1: _rebuild_loadout_tab()
		2: _rebuild_forge_tab()
	_animate_tab_switch(idx)
	_update_bottom_forge_controls()

func _update_tab_style() -> void:
	for i in _tab_btns.size():
		UITheme.apply_button_theme(_tab_btns[i] as Button, i == _active_tab)

func _tab_control(idx: int) -> Control:
	match idx:
		0: return _tab_team
		1: return _tab_loadout
		2: return _tab_forge
	return _tab_team

func _animate_tab_switch(new_idx: int) -> void:
	if _tab_anim_tween and _tab_anim_tween.is_valid():
		_tab_anim_tween.kill()
	var old_tab: Control = _tab_control(_active_tab)
	var new_tab: Control = _tab_control(new_idx)
	var old_idx = _active_tab
	_active_tab = new_idx
	_update_tab_style()

	old_tab.visible = true
	new_tab.visible = true
	new_tab.modulate.a = 0.0
	var dir = 1.0 if new_idx > old_idx else -1.0
	var old_start = old_tab.position
	var new_start = new_tab.position
	old_tab.position = Vector2(0, 0)
	new_tab.position = Vector2(22.0 * dir, 0)

	_tab_anim_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tab_anim_tween.tween_property(old_tab, "modulate:a", 0.0, 0.14)
	_tab_anim_tween.tween_property(old_tab, "position:x", -18.0 * dir, 0.14)
	_tab_anim_tween.tween_property(new_tab, "modulate:a", 1.0, 0.18)
	_tab_anim_tween.tween_property(new_tab, "position:x", 0.0, 0.18)
	_tab_anim_tween.finished.connect(func():
		if is_instance_valid(old_tab):
			old_tab.visible = false
			old_tab.modulate.a = 1.0
			old_tab.position = old_start
		if is_instance_valid(new_tab):
			new_tab.position = new_start
	)

func _update_next_button() -> void:
	var was_disabled = _next_btn.disabled
	_next_btn.disabled = not PlayerInventory.can_start_round()
	if was_disabled and not _next_btn.disabled:
		_pulse_next_button()

# ── Next round ────────────────────────────────────────────────────────────────

func _on_backdrop_clicked(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if _picker_overlay != null and _picker_overlay.visible:
		return
	if _panel.get_global_rect().has_point(mb.global_position):
		return
	_continue_to_next_level()

func _continue_to_next_level() -> void:
	if _next_btn.disabled or not PlayerInventory.can_start_round():
		return
	_on_next_round_pressed()

func _on_next_round_pressed() -> void:
	_next_btn.disabled = true
	_hide_tooltip()
	next_round_pressed.emit()
	var tw = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(_panel, "position", Vector2(PANEL_X, PANEL_Y - 540), 0.35)
	await tw.finished
	visible = false
