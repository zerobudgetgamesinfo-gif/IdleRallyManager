extends VBoxContainer
## Temporary driver and car pick. Phase 5 deletes this script and its nodes.

const TEXT_COLOR := Color(0.973, 0.941, 0.878, 1.0)
const FONT_SIZE := 14

var clock: Callable = Callable()

var _drivers: OptionButton
var _cars: OptionButton
var _budget: Label
var _confirm: Button


func _ready() -> void:
	name = "DraftPlaceholder"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 4)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_drivers = _option()
	_cars = _option()
	_fill_drivers()
	_fill_cars()
	row.add_child(_drivers)
	row.add_child(_cars)
	_budget = Label.new()
	_budget.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_budget.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_budget.add_theme_font_size_override("font_size", FONT_SIZE)
	_budget.add_theme_color_override("font_color", TEXT_COLOR)
	row.add_child(_budget)
	_confirm = Button.new()
	_confirm.text = "Confirm"
	_confirm.focus_mode = Control.FOCUS_NONE
	_confirm.disabled = true
	_confirm.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_confirm.custom_minimum_size = Vector2(96, 28)
	_confirm.add_theme_font_size_override("font_size", FONT_SIZE)
	_confirm.pressed.connect(_on_confirm_pressed)
	row.add_child(_confirm)
	add_child(row)
	_drivers.item_selected.connect(_on_pick_changed)
	_cars.item_selected.connect(_on_pick_changed)
	_silence_popup(_drivers)
	_silence_popup(_cars)
	_refresh()


func _option() -> OptionButton:
	var option := OptionButton.new()
	option.focus_mode = Control.FOCUS_NONE
	option.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option.custom_minimum_size = Vector2(160, 28)
	option.add_theme_font_size_override("font_size", FONT_SIZE)
	return option


func _fill_drivers() -> void:
	_drivers.clear()
	for driver in Session.CATALOG.drivers:
		if driver == null or driver.id == "":
			continue
		var index := _drivers.item_count
		_drivers.add_item("%s  %d" % [driver.display_name, driver.cost])
		_drivers.set_item_metadata(index, driver.id)


func _fill_cars() -> void:
	_cars.clear()
	for car in Session.CATALOG.cars:
		if car == null or car.id == "":
			continue
		var index := _cars.item_count
		_cars.add_item("%s  %d" % [car.display_name, car.cost])
		_cars.set_item_metadata(index, car.id)


func _silence_popup(option: OptionButton) -> void:
	var popup := option.get_popup()
	popup.unfocusable = true


func _on_pick_changed(_index: int) -> void:
	_refresh()


func _refresh() -> void:
	var driver := Session.CATALOG.driver(_selected_id(_drivers))
	var car := Session.CATALOG.car(_selected_id(_cars))
	var cost := 0
	if driver != null:
		cost += driver.cost
	if car != null:
		cost += car.cost
	var legal := driver != null and car != null and cost <= Championship.BUDGET
	if legal:
		var spare := Championship.BUDGET - cost
		_budget.text = "Budget %d/%d   spare +%d" % [cost, Championship.BUDGET, spare]
	else:
		_budget.text = "Budget %d/%d" % [cost, Championship.BUDGET]
	_confirm.disabled = not legal


func _selected_id(option: OptionButton) -> String:
	var index := option.selected
	if index < 0:
		return ""
	return str(option.get_item_metadata(index))


func _on_confirm_pressed() -> void:
	var now := Time.get_unix_time_from_system()
	if clock.is_valid():
		now = float(clock.call())
	Session.confirm_draft(_selected_id(_drivers), _selected_id(_cars), now)
