class_name DraftView
extends Control
## Budget draft: driver and car columns, live total, stage 1 hint, confirm.

const TEXT_COLOR := Color(0.973, 0.941, 0.878, 1.0)
const MUTED_COLOR := Color(0.973, 0.941, 0.878, 0.72)
const FONT_SIZE := 14
const FONT_SIZE_COMPACT := 12
const ROW_HEIGHT := 28.0
const ROW_HEIGHT_COMPACT := 24.0
const SELECTED_BG := Color(0.42, 0.48, 0.34, 1.0)
const ROW_BG := Color(0.22, 0.20, 0.17, 0.85)

var clock: Callable = Callable()

var _driver_id := ""
var _car_id := ""
var _driver_group: ButtonGroup
var _car_group: ButtonGroup
var _hint: Label
var _total: Label
var _good_at: Label
var _confirm: Button
var _drivers_box: VBoxContainer
var _cars_box: VBoxContainer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_driver_group = ButtonGroup.new()
	_car_group = ButtonGroup.new()
	_build()
	resized.connect(_on_resized)
	_refresh_summary()


func _build() -> void:
	var root := VBoxContainer.new()
	root.name = "DraftRoot"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 4)
	add_child(root)

	_hint = _make_label(_stage_hint_text(), MUTED_COLOR)
	_hint.name = "Hint"
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_hint)

	var columns := HBoxContainer.new()
	columns.name = "Columns"
	columns.mouse_filter = Control.MOUSE_FILTER_IGNORE
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 8)
	root.add_child(columns)

	_drivers_box = _column(columns, "Drivers")
	_cars_box = _column(columns, "Cars")

	_total = _make_label("", TEXT_COLOR)
	_total.name = "Total"
	_total.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_total)

	_good_at = _make_label("", MUTED_COLOR)
	_good_at.name = "GoodAt"
	_good_at.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_good_at)

	_confirm = Button.new()
	_confirm.name = "Confirm"
	_confirm.text = "Confirm"
	_confirm.focus_mode = Control.FOCUS_NONE
	_confirm.disabled = true
	_confirm.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_confirm.custom_minimum_size = Vector2(120, 28)
	_confirm.add_theme_font_size_override("font_size", FONT_SIZE)
	_confirm.pressed.connect(_on_confirm_pressed)
	root.add_child(_confirm)

	_fill_drivers()
	_fill_cars()
	_apply_compact_layout()


func _column(parent: HBoxContainer, title: String) -> VBoxContainer:
	var wrap := VBoxContainer.new()
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_theme_constant_override("separation", 2)
	var heading := _make_label(title, MUTED_COLOR)
	wrap.add_child(heading)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.focus_mode = Control.FOCUS_NONE
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	wrap.add_child(scroll)
	var list := VBoxContainer.new()
	list.name = "List"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	list.add_theme_constant_override("separation", 2)
	scroll.add_child(list)
	parent.add_child(wrap)
	return list


func _fill_drivers() -> void:
	for child in _drivers_box.get_children():
		child.queue_free()
	for driver in Session.CATALOG.drivers:
		if driver == null or driver.id == "":
			continue
		_drivers_box.add_child(_row_button(driver.id, true))


func _fill_cars() -> void:
	for child in _cars_box.get_children():
		child.queue_free()
	for car in Session.CATALOG.cars:
		if car == null or car.id == "":
			continue
		_cars_box.add_child(_row_button(car.id, false))


func _row_button(item_id: String, is_driver: bool) -> Button:
	var button := Button.new()
	button.toggle_mode = true
	button.button_group = _driver_group if is_driver else _car_group
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.set_meta("item_id", item_id)
	button.set_meta("is_driver", is_driver)
	_style_row(button, false)
	button.toggled.connect(_on_row_toggled.bind(button))
	_set_row_text(button)
	return button


func _style_row(button: Button, selected: bool) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = SELECTED_BG if selected else ROW_BG
	style.set_corner_radius_all(4)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", style)
	button.add_theme_stylebox_override("pressed", style)
	button.add_theme_stylebox_override("focus", style)
	button.add_theme_color_override("font_color", TEXT_COLOR)
	button.add_theme_color_override("font_hover_color", TEXT_COLOR)
	button.add_theme_color_override("font_pressed_color", TEXT_COLOR)


func _set_row_text(button: Button) -> void:
	var item_id := str(button.get_meta("item_id", ""))
	var is_driver := bool(button.get_meta("is_driver", false))
	var compact := _is_compact()
	var font := FONT_SIZE_COMPACT if compact else FONT_SIZE
	button.add_theme_font_size_override("font_size", font)
	button.custom_minimum_size = Vector2(0, ROW_HEIGHT_COMPACT if compact else ROW_HEIGHT)
	if is_driver:
		var driver := Session.CATALOG.driver(item_id)
		if driver == null:
			button.text = item_id
			return
		var name := _short_name(driver.display_name) if compact else driver.display_name
		button.text = "%s  %d  %s" % [name, driver.cost, _two_stat_text_driver(driver)]
	else:
		var car := Session.CATALOG.car(item_id)
		if car == null:
			button.text = item_id
			return
		var car_name := car.display_name
		button.text = "%s  %d  %s" % [car_name, car.cost, _two_stat_text_car(car)]


func _two_stat_text_driver(driver: DriverDef) -> String:
	return _format_two_stats(func(stat_name: String) -> int:
		return driver.stat(stat_name)
	)


func _two_stat_text_car(car: CarDef) -> String:
	return _format_two_stats(func(stat_name: String) -> int:
		return car.stat(stat_name)
	)


func _format_two_stats(getter: Callable) -> String:
	var ranked := _rank_stats(getter)
	if ranked.size() < 2:
		return ""
	var a: Dictionary = ranked[0]
	var b: Dictionary = ranked[1]
	return "%s %d · %s %d" % [
		_stat_word(str(a["name"])),
		int(a["value"]),
		_stat_word(str(b["name"])),
		int(b["value"]),
	]


func _on_row_toggled(pressed: bool, button: Button) -> void:
	_style_row(button, pressed)
	if not pressed:
		_refresh_summary()
		return
	var item_id := str(button.get_meta("item_id", ""))
	if bool(button.get_meta("is_driver", false)):
		_driver_id = item_id
	else:
		_car_id = item_id
	_refresh_summary()


func _refresh_summary() -> void:
	var driver := Session.CATALOG.driver(_driver_id)
	var car := Session.CATALOG.car(_car_id)
	var cost := 0
	if driver != null:
		cost += driver.cost
	if car != null:
		cost += car.cost
	var remaining := Championship.BUDGET - cost
	var legal := driver != null and car != null and cost <= Championship.BUDGET
	if legal:
		_total.text = "Spent %d / %d · remaining %d · +%d reliability" % [
			cost,
			Championship.BUDGET,
			remaining,
			remaining,
		]
		_good_at.text = "Good at: %s" % _pair_good_at(driver, car)
	elif driver == null or car == null:
		_total.text = "Spent %d / %d · pick a driver and a car" % [cost, Championship.BUDGET]
		_good_at.text = ""
	else:
		_total.text = "Spent %d / %d · over budget" % [cost, Championship.BUDGET]
		_good_at.text = ""
	_confirm.disabled = not legal
	_good_at.visible = _good_at.text != "" and not _is_compact()


func _pair_good_at(driver: DriverDef, car: CarDef) -> String:
	var ranked := _rank_stats(func(stat_name: String) -> int:
		return driver.stat(stat_name) + car.stat(stat_name)
	)
	if ranked.size() < 2:
		return ""
	return "%s and %s" % [
		_stat_word(str(ranked[0]["name"])),
		_stat_word(str(ranked[1]["name"])),
	]


func _rank_stats(getter: Callable) -> Array[Dictionary]:
	var ranked: Array[Dictionary] = []
	for stat_name in Entry.STAT_NAMES:
		ranked.append({
			"name": String(stat_name),
			"value": int(getter.call(String(stat_name))),
		})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var av := int(a["value"])
		var bv := int(b["value"])
		if av != bv:
			return av > bv
		return str(a["name"]) < str(b["name"])
	)
	return ranked


func _stage_hint_text() -> String:
	var stage := Session.CATALOG.stage_at(0)
	if stage == null:
		return "Stage 1 hint unavailable"
	var top := ServiceOffer.top_stat(stage)
	return "Stage 1: %s · %s · %s" % [stage.display_name, stage.surface, _stat_word(top)]


func _stat_word(stat_name: String) -> String:
	if stat_name.is_empty():
		return stat_name
	return stat_name.capitalize()


func _short_name(display_name: String) -> String:
	if display_name.is_empty():
		return display_name
	return display_name.get_slice(" ", 0)


func _is_compact() -> bool:
	return Dock.get_preset() == Dock.PRESET_COMPACT


func _on_resized() -> void:
	_apply_compact_layout()


func _apply_compact_layout() -> void:
	var compact := _is_compact()
	var font := FONT_SIZE_COMPACT if compact else FONT_SIZE
	if _hint != null:
		_hint.add_theme_font_size_override("font_size", font)
	if _total != null:
		_total.add_theme_font_size_override("font_size", font)
	if _good_at != null:
		_good_at.add_theme_font_size_override("font_size", font)
		_good_at.visible = _good_at.text != "" and not compact
	if _confirm != null:
		_confirm.add_theme_font_size_override("font_size", font)
		_confirm.custom_minimum_size = Vector2(96 if compact else 120, 24 if compact else 28)
	for button in _drivers_box.get_children():
		if button is Button:
			_set_row_text(button as Button)
	for button in _cars_box.get_children():
		if button is Button:
			_set_row_text(button as Button)


func _make_label(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_color", color)
	return label


func _on_confirm_pressed() -> void:
	var now := Time.get_unix_time_from_system()
	if clock.is_valid():
		now = float(clock.call())
	Session.confirm_draft(_driver_id, _car_id, now)
