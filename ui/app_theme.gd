class_name AppTheme
extends RefCounted
## Builds the shared Theme in code so colors and radii come from Palette and Style.

const TITLE_FONT := preload("res://ui/fonts/fredoka.ttf")
const BODY_FONT := preload("res://ui/fonts/nunito.ttf")

const BASE_SIZE := 14


static func build() -> Theme:
	var theme := Theme.new()
	theme.default_font = BODY_FONT
	theme.default_font_size = BASE_SIZE
	_colors(theme)
	_buttons(theme)
	_containers(theme)
	theme.set_font("font", "TitleLabel", TITLE_FONT)
	theme.set_type_variation("TitleLabel", "Label")
	theme.set_font_size("font_size", "TitleLabel", 18)
	return theme


static func _colors(theme: Theme) -> void:
	for type_name in ["Label", "Button", "CheckBox", "RichTextLabel"]:
		var key := "default_color" if type_name == "RichTextLabel" else "font_color"
		theme.set_color(key, type_name, Palette.CREAM)
	for type_name in ["Button", "CheckBox"]:
		theme.set_color("font_hover_color", type_name, Palette.CREAM)
		theme.set_color("font_pressed_color", type_name, Palette.CREAM)
		theme.set_color("font_hover_pressed_color", type_name, Palette.CREAM)
		theme.set_color("font_disabled_color", type_name, Palette.CREAM_MUTED)
	theme.set_color("font_outline_color", "Label", Palette.INK)


static func _buttons(theme: Theme) -> void:
	var normal := _button_box(Palette.BROWN_LIGHT, Palette.AMBER_DEEP)
	var hover := _button_box(Palette.BROWN_LIGHT.lightened(0.12), Palette.AMBER)
	var pressed := _button_box(Palette.SAGE, Palette.AMBER_LIGHT)
	pressed.shadow_size = 0
	pressed.content_margin_top += 1
	var disabled := _button_box(Palette.BROWN, Palette.BROWN_LIGHT)
	disabled.shadow_size = 0
	var focus := StyleBoxEmpty.new()
	for type_name in ["Button", "CheckBox"]:
		theme.set_stylebox("normal", type_name, normal)
		theme.set_stylebox("hover", type_name, hover)
		theme.set_stylebox("pressed", type_name, pressed)
		theme.set_stylebox("hover_pressed", type_name, pressed)
		theme.set_stylebox("disabled", type_name, disabled)
		theme.set_stylebox("focus", type_name, focus)
	# Checkboxes read as plain toggles: keep the check icon, drop the heavy frame.
	var plain := Style.box(Color(0, 0, 0, 0), 6)
	plain.content_margin_left = 4
	plain.content_margin_right = 4
	theme.set_stylebox("normal", "CheckBox", plain)
	theme.set_stylebox("hover", "CheckBox", plain)
	theme.set_stylebox("pressed", "CheckBox", plain)
	theme.set_stylebox("hover_pressed", "CheckBox", plain)


static func _button_box(fill: Color, border: Color) -> StyleBoxFlat:
	var style := Style.raised(fill, 8, border, 3)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	return style


static func _containers(theme: Theme) -> void:
	theme.set_stylebox("panel", "PanelContainer", Style.raised(Palette.BROWN_DEEP, 8, Palette.BROWN_LIGHT, 0))
	theme.set_stylebox("panel", "Panel", Style.box(Palette.BROWN, Style.RADIUS, Palette.AMBER, 2))
	var grabber := Style.box(Palette.AMBER_DEEP, 4)
	grabber.set_content_margin_all(2)
	var track := Style.box(Color(0, 0, 0, 0.25), 4)
	track.set_content_margin_all(2)
	for type_name in ["VScrollBar", "HScrollBar"]:
		theme.set_stylebox("scroll", type_name, track)
		theme.set_stylebox("grabber", type_name, grabber)
		theme.set_stylebox("grabber_highlight", type_name, Style.box(Palette.AMBER, 4))
		theme.set_stylebox("grabber_pressed", type_name, Style.box(Palette.AMBER_LIGHT, 4))
