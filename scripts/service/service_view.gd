class_name ServiceView
extends Control
## Three service cards and next-stage hint. Remaining time lives in the strip header.
## The park behind them is one still illustration. Only the card pulse repeats,
## and only while the player has not chosen. On the left-edge column `vertical` is
## set before add_child and the cards stack.

const PARK_TEXTURE: Texture2D = preload("res://scenes/service/art/park.svg")
const TEXT_COLOR := Palette.CREAM
const MUTED_COLOR := Palette.CREAM_MUTED
const FONT_SIZE := 14
const FONT_SIZE_AWAY := 12
const FONT_SIZE_VERTICAL := 12
const CARD_MIN_HEIGHT := 80.0
const ICON_SIZE := 30.0
const PULSE_SEC := 1.0

## Stack the cards instead of laying them in a row.
var vertical := false

var _root: VBoxContainer
var _hint: Label
var _card_row: BoxContainer
var _cards: Array[PanelContainer] = []
var _pulse: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	_apply_selection_visuals()
	_sync_pulse()
	if vertical:
		resized.connect(_fit_height)
		_fit_height.call_deferred()


func _exit_tree() -> void:
	_stop_pulse()


func _build() -> void:
	var park := TextureRect.new()
	park.name = "Park"
	park.texture = PARK_TEXTURE
	park.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	park.stretch_mode = TextureRect.STRETCH_TILE
	park.mouse_filter = Control.MOUSE_FILTER_IGNORE
	park.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(park)

	_root = VBoxContainer.new()
	_root.name = "ServiceRoot"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_theme_constant_override("separation", 8)
	add_child(_root)

	var backdrop := PanelContainer.new()
	backdrop.name = "HintBackdrop"
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.add_theme_stylebox_override("panel", Style.backdrop())
	_root.add_child(backdrop)

	_hint = _make_label(_next_hint_text(), TEXT_COLOR)
	_hint.name = "Hint"
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	backdrop.add_child(_hint)

	_card_row = VBoxContainer.new() if vertical else HBoxContainer.new()
	_card_row.name = "Cards"
	_card_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_card_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_card_row.add_theme_constant_override("separation", 8)
	_root.add_child(_card_row)

	_fill_cards()


## Stacked cards decide their own height; the view reports it so the column below can sit under it.
func _fit_height() -> void:
	if _root == null:
		return
	var wanted := _root.get_combined_minimum_size().y
	if not is_equal_approx(custom_minimum_size.y, wanted):
		custom_minimum_size.y = wanted


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
	panel.custom_minimum_size = Vector2(0, CARD_MIN_HEIGHT)
	panel.accessibility_name = card.label
	panel.accessibility_description = _card_description(card)
	panel.set_meta("card_id", card.id)
	panel.set_meta("safe", card.safe)
	panel.gui_input.connect(_on_card_gui_input.bind(card.id))

	var body := HBoxContainer.new()
	body.name = "Body"
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_theme_constant_override("separation", 8)
	panel.add_child(body)

	body.add_child(Widgets.stat_icon(_icon_stat(card), ICON_SIZE))

	var text_box := VBoxContainer.new()
	text_box.name = "Text"
	text_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text_box.add_theme_constant_override("separation", 2)
	body.add_child(text_box)

	var title := _make_label("", TEXT_COLOR)
	title.name = "Title"
	title.theme_type_variation = &"TitleLabel"
	title.add_theme_font_size_override("font_size", FONT_SIZE + 1)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_box.add_child(title)

	var delta := _make_label("", MUTED_COLOR)
	delta.name = "Delta"
	delta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.add_child(delta)

	var away := _make_label("", MUTED_COLOR)
	away.name = "Away"
	away.add_theme_font_size_override("font_size", FONT_SIZE_AWAY)
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
	panel.add_theme_stylebox_override("panel", Style.card(selected))


func _set_card_text(panel: PanelContainer, card: CardDef) -> void:
	var chosen := _chosen_id()
	var selected := card.id == chosen and chosen != ""
	var title := panel.get_node_or_null("Body/Text/Title") as Label
	var delta := panel.get_node_or_null("Body/Text/Delta") as Label
	var away := panel.get_node_or_null("Body/Text/Away") as Label
	if title != null:
		var check := "✓ " if selected else ""
		title.text = "%s%s" % [check, card.label]
	if delta != null:
		delta.text = _delta_text(card)
	if away != null:
		if card.safe:
			away.visible = true
			away.text = "If you step away: this one"
		else:
			away.visible = false
			away.text = ""
	panel.accessibility_description = _card_description(card)


## Said by tools that walk the tree: the effect, the default, and whether it is the current pick.
func _card_description(card: CardDef) -> String:
	var parts: PackedStringArray = [_delta_text(card)]
	if card.safe:
		parts.append("This is the card applied if you step away")
	var chosen := _chosen_id()
	if chosen != "" and card.id == chosen:
		parts.append("Selected")
	return ". ".join(parts)


func _delta_text(card: CardDef) -> String:
	var parts: PackedStringArray = []
	for stat_name in Entry.STAT_NAMES:
		var amount := card.delta(String(stat_name))
		if amount == 0:
			continue
		parts.append("%s %s %d" % ["▲" if amount > 0 else "▼", String(stat_name).capitalize(), absi(amount)])
	if parts.is_empty():
		return "—"
	return ", ".join(parts)


## The first stat the card raises picks its icon.
func _icon_stat(card: CardDef) -> String:
	for stat_name in Entry.STAT_NAMES:
		if card.delta(String(stat_name)) > 0:
			return String(stat_name)
	return "none"


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


func _make_label(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", FONT_SIZE_VERTICAL if vertical else FONT_SIZE)
	label.add_theme_color_override("font_color", color)
	return label
