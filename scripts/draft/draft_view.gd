class_name DraftView
extends Control
## Budget draft for focus height: driver and car columns, live total, stage 1 hint, confirm.
## On the left-edge column `vertical` is set before add_child and the columns stack.
## A selected row carries a check mark, so selection is never color alone.

const TEXT_COLOR := Palette.CREAM
const MUTED_COLOR := Palette.CREAM_MUTED
const FONT_SIZE := 14
const FONT_SIZE_VERTICAL := 12
const ROW_HEIGHT := 34.0
const ICON_EDGE := 28

var clock: Callable = Callable()
## Stack the driver and car lists instead of placing them side by side.
var vertical := false

var _driver_id := ""
var _car_id := ""
var _driver_group: ButtonGroup
var _car_group: ButtonGroup
var _hint: Label
var _total: Label
var _meter: ProgressBar
var _good_at: Label
var _confirm: Button
var _drivers_box: VBoxContainer
var _cars_box: VBoxContainer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_driver_group = ButtonGroup.new()
	_car_group = ButtonGroup.new()
	_build()
	_refresh_summary()


func _build() -> void:
	var root := VBoxContainer.new()
	root.name = "DraftRoot"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	_hint = _make_label(_stage_hint_text(), MUTED_COLOR)
	_hint.name = "Hint"
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_hint)

	var reputation := _make_label("Reputation %d" % Session.garage.reputation, MUTED_COLOR)
	reputation.name = "Reputation"
	root.add_child(reputation)

	var columns: BoxContainer = VBoxContainer.new() if vertical else HBoxContainer.new()
	columns.name = "Columns"
	columns.mouse_filter = Control.MOUSE_FILTER_IGNORE
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 10)
	if vertical:
		# One scroll for both lists; the total and Confirm stay pinned below it.
		var shared := _make_scroll()
		root.add_child(shared)
		shared.add_child(columns)
	else:
		root.add_child(columns)

	_drivers_box = _column(columns, "Drivers")
	_cars_box = _column(columns, "Cars")

	_meter = ProgressBar.new()
	_meter.name = "Budget"
	_meter.min_value = 0.0
	_meter.max_value = float(Championship.BUDGET)
	_meter.show_percentage = false
	_meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_meter.custom_minimum_size = Vector2(0, 8)
	_meter.add_theme_stylebox_override("background", Style.box(Color(0, 0, 0, 0.35), 4))
	_meter.add_theme_stylebox_override("fill", Style.box(Palette.AMBER, 4))
	root.add_child(_meter)

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
	_confirm.custom_minimum_size = Vector2(120, 30)
	_confirm.add_theme_font_size_override("font_size", _font_size())
	_confirm.accessibility_name = "Confirm draft"
	_confirm.accessibility_description = "Locks the chosen driver and car and starts the championship."
	if vertical:
		_confirm.custom_minimum_size = Vector2(0, 30)
	_confirm.pressed.connect(_on_confirm_pressed)
	root.add_child(_confirm)

	_fill_drivers()
	_fill_cars()


func _make_scroll() -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.focus_mode = Control.FOCUS_NONE
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	return scroll


func _column(parent: BoxContainer, title: String) -> VBoxContainer:
	var wrap := VBoxContainer.new()
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL if not vertical else Control.SIZE_SHRINK_BEGIN
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_theme_constant_override("separation", 4)
	var heading := _make_label(title, Palette.AMBER_LIGHT)
	heading.theme_type_variation = &"TitleLabel"
	heading.add_theme_font_size_override("font_size", _font_size() + 2)
	wrap.add_child(heading)
	var list := VBoxContainer.new()
	list.name = "List"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	list.add_theme_constant_override("separation", 4)
	if vertical:
		wrap.add_child(list)
	else:
		var scroll := _make_scroll()
		wrap.add_child(scroll)
		scroll.add_child(list)
	parent.add_child(wrap)
	return list


func _fill_drivers() -> void:
	for child in _drivers_box.get_children():
		child.queue_free()
	for driver in Session.CATALOG.drivers:
		if driver == null or driver.id == "":
			continue
		if Session.garage.allows(driver.unlock_reputation, driver.id):
			_drivers_box.add_child(_row_button(driver.id, true))
		else:
			_drivers_box.add_child(_locked_row(driver.display_name, driver.unlock_reputation))


func _fill_cars() -> void:
	for child in _cars_box.get_children():
		child.queue_free()
	for car in Session.CATALOG.cars:
		if car == null or car.id == "":
			continue
		if not Session.garage.allows(car.unlock_reputation, car.id):
			_cars_box.add_child(_locked_row(car.display_name, car.unlock_reputation))
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
	if vertical:
		# The column is narrow: wrap the row instead of cutting the numbers off.
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	else:
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	button.add_theme_font_size_override("font_size", _font_size())
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", ICON_EDGE)
	button.set_meta("item_id", item_id)
	button.set_meta("is_driver", is_driver)
	_style_row(button, false)
	button.toggled.connect(_on_row_toggled.bind(button))
	_set_row_text(button)
	return button


func _locked_row(title: String, threshold: int) -> Label:
	var row := _make_label("%s  ·  %d reputation" % [title, threshold], MUTED_COLOR)
	row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.accessibility_name = "%s, locked until %d reputation" % [title, threshold]
	return row


func _style_row(button: Button, selected: bool) -> void:
	var style := Style.card(selected)
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	var hover := Style.card(selected, true)
	hover.content_margin_top = 4
	hover.content_margin_bottom = 4
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", style)
	button.add_theme_stylebox_override("hover_pressed", hover)
	button.add_theme_stylebox_override("focus", style)
	button.add_theme_color_override("font_color", TEXT_COLOR)
	button.add_theme_color_override("font_hover_color", TEXT_COLOR)
	button.add_theme_color_override("font_pressed_color", TEXT_COLOR)


func _set_row_text(button: Button) -> void:
	var item_id := str(button.get_meta("item_id", ""))
	var is_driver := bool(button.get_meta("is_driver", false))
	var check := "✓ " if button.button_pressed else ""
	var kind := "driver" if is_driver else "car"
	var summary := ""
	var title := item_id
	var cost := 0
	if is_driver:
		var driver := Session.CATALOG.driver(item_id)
		if driver != null:
			title = driver.display_name
			cost = driver.cost
			summary = _two_stat_text_driver(driver)
			button.icon = driver.portrait
	else:
		var car := Session.CATALOG.car(item_id)
		if car != null:
			title = car.display_name
			cost = car.cost
			summary = _two_stat_text_car(car)
			button.icon = car.portrait
	if summary == "":
		button.text = "%s%s" % [check, title]
	else:
		button.text = "%s%s  %d  %s" % [check, title, cost, summary]
	button.accessibility_name = "%s %s, cost %d" % [kind, title, cost]
	button.accessibility_description = "%s. %s." % [
		"Selected" if button.button_pressed else "Not selected",
		summary if summary != "" else "No stats",
	]


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
	_set_row_text(button)
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
	_meter.value = minf(float(cost), float(Championship.BUDGET))
	var over := cost > Championship.BUDGET
	_meter.add_theme_stylebox_override("fill", Style.box(Palette.CLAY if over else Palette.AMBER, 4))
	_good_at.visible = _good_at.text != ""


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


func _make_label(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", _font_size())
	label.add_theme_color_override("font_color", color)
	return label


func _font_size() -> int:
	return FONT_SIZE_VERTICAL if vertical else FONT_SIZE


func _on_confirm_pressed() -> void:
	var now := Time.get_unix_time_from_system()
	if clock.is_valid():
		now = float(clock.call())
	Session.confirm_draft(_driver_id, _car_id, now)
