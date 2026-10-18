class_name ServiceView
extends Control
## Three service cards, next-stage hint, remaining time, and an idle pulse while unpicked.

const TEXT_COLOR := Color(0.973, 0.941, 0.878, 1.0)
const MUTED_COLOR := Color(0.973, 0.941, 0.878, 0.72)
const PARK_COLOR := Color(0.34, 0.40, 0.30, 1.0)
const CARD_BG := Color(0.22, 0.20, 0.17, 0.92)
const CARD_SELECTED := Color(0.42, 0.48, 0.34, 1.0)
const ICON_COLORS := {
	"pace": Color(0.72, 0.42, 0.28, 1.0),
	"grip": Color(0.38, 0.58, 0.42, 1.0),
	"jump": Color(0.42, 0.52, 0.72, 1.0),
	"reliability": Color(0.62, 0.55, 0.32, 1.0),
	"focus": Color(0.55, 0.42, 0.62, 1.0),
}
const FONT_SIZE := 14
const FONT_SIZE_COMPACT := 12
const PULSE_SEC := 1.0

var clock: Callable = Callable()

var _hint: Label
var _timer_label: Label
var _card_row: HBoxContainer
var _cards: Array[PanelContainer] = []
var _pulse: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	resized.connect(_on_resized)
	_apply_selection_visuals()
	_sync_pulse()
	refresh_clock()


func _exit_tree() -> void:
	_stop_pulse()


func refresh_clock() -> void:
	if _timer_label == null:
		return
	_timer_label.text = "%s left" % _format_mmss(Session.remaining(_now()))


func _build() -> void:
	var park := ColorRect.new()
	park.name = "Park"
	park.mouse_filter = Control.MOUSE_FILTER_IGNORE
	park.color = PARK_COLOR
	park.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(park)

	var root := VBoxContainer.new()
	root.name = "ServiceRoot"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 4)
	add_child(root)

	_hint = _make_label(_next_hint_text(), MUTED_COLOR)
	_hint.name = "Hint"
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_hint)

	_timer_label = _make_label("", TEXT_COLOR)
	_timer_label.name = "Timer"
	root.add_child(_timer_label)

	_card_row = HBoxContainer.new()
	_card_row.name = "Cards"
	_card_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_card_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_card_row.add_theme_constant_override("separation", 6)
	root.add_child(_card_row)

	_fill_cards()
	_apply_compact_layout()


func _fill_cards() -> void:
	for child in _card_row.get_children():
		child.queue_free()
	_cards.clear()
	var offer := _player_offer()
	var ids: Variant = offer.get("card_ids", [])
	if not ids is Array:
		return
	for raw_id in ids:
		var card_id := str(raw_id)
		var card := Session.CATALOG.card(card_id)
		if card == null:
			continue
		var panel := _card_panel(card)
		_card_row.add_child(panel)
		_cards.append(panel)


func _card_panel(card: CardDef) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = card.id
	panel.focus_mode = Control.FOCUS_NONE
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(0, 36)
	panel.set_meta("card_id", card.id)
	panel.set_meta("safe", card.safe)
	panel.gui_input.connect(_on_card_gui_input.bind(card.id))

	var body := HBoxContainer.new()
	body.name = "Body"
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_theme_constant_override("separation", 6)
	panel.add_child(body)

	var icon := ColorRect.new()
	icon.name = "Icon"
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.custom_minimum_size = Vector2(14, 14)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.color = _icon_color(card)
	body.add_child(icon)

	var text_box := VBoxContainer.new()
	text_box.name = "Text"
	text_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text_box.add_theme_constant_override("separation", 1)
	body.add_child(text_box)

	var title := _make_label("", TEXT_COLOR)
	title.name = "Title"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.clip_text = true
	text_box.add_child(title)

	var delta := _make_label("", MUTED_COLOR)
	delta.name = "Delta"
	delta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	delta.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	delta.clip_text = true
	text_box.add_child(delta)

	var away := _make_label("", MUTED_COLOR)
	away.name = "Away"
	away.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_box.add_child(away)

	_style_card(panel, false)
	_set_card_text(panel, card)
	return panel


func _on_card_gui_input(event: InputEvent, card_id: String) -> void:
	if not event is InputEventMouseButton:
		return
	var button := event as InputEventMouseButton
	if button.button_index != MOUSE_BUTTON_LEFT or not button.pressed:
		return
	_on_card_pressed(card_id)
	accept_event()


func _style_card(panel: PanelContainer, selected: bool) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = CARD_SELECTED if selected else CARD_BG
	style.set_corner_radius_all(6)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)


func _set_card_text(panel: PanelContainer, card: CardDef) -> void:
	var compact := _is_compact()
	var font := FONT_SIZE_COMPACT if compact else FONT_SIZE
	var chosen := _chosen_id()
	var selected := card.id == chosen and chosen != ""
	var title := panel.get_node_or_null("Body/Text/Title") as Label
	var delta := panel.get_node_or_null("Body/Text/Delta") as Label
	var away := panel.get_node_or_null("Body/Text/Away") as Label
	if title != null:
		title.add_theme_font_size_override("font_size", font)
		var check := "✓ " if selected else ""
		if compact:
			title.text = "%s%s" % [check, card.label.get_slice(" ", 0)]
		else:
			title.text = "%s%s" % [check, card.label]
	if delta != null:
		delta.add_theme_font_size_override("font_size", font)
		delta.text = _delta_text(card)
	if away != null:
		away.add_theme_font_size_override("font_size", FONT_SIZE_COMPACT)
		if card.safe:
			away.visible = true
			away.text = "away default" if compact else "If you step away: this one"
		else:
			away.visible = false
			away.text = ""


func _delta_text(card: CardDef) -> String:
	var parts: PackedStringArray = []
	for stat_name in Entry.STAT_NAMES:
		var amount := card.delta(String(stat_name))
		if amount == 0:
			continue
		parts.append("%s %+d" % [String(stat_name).capitalize(), amount])
	if parts.is_empty():
		return "—"
	return ", ".join(parts)


func _icon_color(card: CardDef) -> Color:
	for stat_name in Entry.STAT_NAMES:
		if card.delta(String(stat_name)) > 0:
			return ICON_COLORS.get(String(stat_name), Color(0.55, 0.50, 0.42, 1.0))
	return Color(0.55, 0.50, 0.42, 1.0)


func _on_card_pressed(card_id: String) -> void:
	if not Session.choose_card(card_id):
		return
	_apply_selection_visuals()
	_sync_pulse()


func _apply_selection_visuals() -> void:
	var chosen := _chosen_id()
	for panel in _cards:
		if not is_instance_valid(panel):
			continue
		var card_id := str(panel.get_meta("card_id", ""))
		var card := Session.CATALOG.card(card_id)
		if card == null:
			continue
		_style_card(panel, card_id == chosen and chosen != "")
		_set_card_text(panel, card)


func _sync_pulse() -> void:
	if _chosen_id() != "":
		_stop_pulse()
		return
	_start_pulse()


func _start_pulse() -> void:
	if _card_row == null:
		return
	if _pulse != null and _pulse.is_valid():
		return
	_stop_pulse()
	_card_row.modulate = Color(1, 1, 1, 1)
	_pulse = create_tween()
	_pulse.set_loops()
	_pulse.tween_property(_card_row, "modulate", Color(1, 1, 1, 0.55), PULSE_SEC)
	_pulse.tween_property(_card_row, "modulate", Color(1, 1, 1, 1.0), PULSE_SEC)


func _stop_pulse() -> void:
	if _pulse != null:
		_pulse.kill()
		_pulse = null
	if _card_row != null:
		_card_row.modulate = Color(1, 1, 1, 1)


func _next_hint_text() -> String:
	var champ := Session.championship
	if champ == null:
		return "Next stage hint unavailable"
	var stage := Session.CATALOG.stage_at(champ.stage_index + 1)
	if stage == null:
		return "No next stage"
	var top := ServiceOffer.top_stat(stage)
	return "Next: %s · %s · %s" % [stage.display_name, stage.surface, top.capitalize()]


func _player_offer() -> Dictionary:
	var champ := Session.championship
	if champ == null:
		return {}
	return champ.offer_for(Championship.PLAYER_ID)


func _chosen_id() -> String:
	return str(_player_offer().get("chosen_card_id", ""))


func _now() -> float:
	if clock.is_valid():
		return float(clock.call())
	return Time.get_unix_time_from_system()


func _format_mmss(seconds: float) -> String:
	var total := maxi(floori(seconds), 0)
	return "%d:%02d" % [int(total / 60.0), total % 60]


func _is_compact() -> bool:
	return Dock.get_preset() == Dock.PRESET_COMPACT


func _on_resized() -> void:
	_apply_compact_layout()


func _apply_compact_layout() -> void:
	var compact := _is_compact()
	var font := FONT_SIZE_COMPACT if compact else FONT_SIZE
	if _hint != null:
		_hint.add_theme_font_size_override("font_size", font)
	if _timer_label != null:
		_timer_label.add_theme_font_size_override("font_size", font)
	for panel in _cards:
		if not is_instance_valid(panel):
			continue
		var card := Session.CATALOG.card(str(panel.get_meta("card_id", "")))
		if card != null:
			_set_card_text(panel, card)


func _make_label(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_color", color)
	return label
