class_name Widgets
extends RefCounted
## Small control factories shared by the phase views.

const MEDAL_COLORS: Array[Color] = [
	Color(0.89, 0.72, 0.28, 1.0),
	Color(0.72, 0.74, 0.78, 1.0),
	Color(0.72, 0.47, 0.30, 1.0),
]
const STAT_ICONS := {
	"pace": preload("res://ui/art/stat_pace.svg"),
	"grip": preload("res://ui/art/stat_grip.svg"),
	"jump": preload("res://ui/art/stat_jump.svg"),
	"reliability": preload("res://ui/art/stat_reliability.svg"),
	"focus": preload("res://ui/art/stat_focus.svg"),
	"none": preload("res://ui/art/stat_none.svg"),
}


static func stat_icon(stat_name: String, edge: float) -> TextureRect:
	var rect := TextureRect.new()
	rect.name = "Icon"
	rect.texture = STAT_ICONS.get(stat_name, STAT_ICONS["none"])
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.custom_minimum_size = Vector2(edge, edge)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return rect


## A round rank badge: gold, silver and bronze for the podium, plain brown after.
static func rank_badge(rank: int, edge := 24.0) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.custom_minimum_size = Vector2(edge, edge)
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fill := Palette.BROWN_LIGHT
	if rank >= 1 and rank <= MEDAL_COLORS.size():
		fill = MEDAL_COLORS[rank - 1]
	var style := Style.box(fill, int(edge * 0.5), Palette.INK, 1)
	style.set_content_margin_all(0)
	panel.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.text = str(rank)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Palette.INK if rank <= MEDAL_COLORS.size() else Palette.CREAM)
	panel.add_child(label)
	return panel


## Wraps a control in a soft row card.
static func row_card(child: Control, highlight := false) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := Style.card(highlight)
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", style)
	panel.add_child(child)
	return panel


## A pill label on a dark chip, readable over any stage surface.
static func chip_label(text: String, fill := Color(0.12, 0.09, 0.07, 0.72)) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", Style.chip(fill))
	var label := Label.new()
	label.name = "Text"
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(label)
	return panel


const HOVER_SCALE := 1.03
const PRESS_SCALE := 0.97
const POP_SEC := 0.1


## Hover grows a control a little and a press squashes it. Each tween is a one-shot that ends in
## 0.1 s and starts only from the pointer, so a still strip has none running.
static func add_pop(control: Control) -> void:
	control.resized.connect(func() -> void: control.pivot_offset = control.size * 0.5)
	control.mouse_entered.connect(_pop.bind(control, HOVER_SCALE))
	control.mouse_exited.connect(_pop.bind(control, 1.0))
	if control is BaseButton:
		control.button_down.connect(_pop.bind(control, PRESS_SCALE))
		control.button_up.connect(_pop.bind(control, HOVER_SCALE))


static func _pop(control: Control, target: float) -> void:
	if not control.is_inside_tree():
		return
	var tween := control.create_tween()
	tween.tween_property(control, "scale", Vector2(target, target), POP_SEC)


## One burst of paper confetti for a win. It emits once and stops.
static func confetti() -> CPUParticles2D:
	var burst := CPUParticles2D.new()
	burst.name = "Confetti"
	burst.one_shot = true
	burst.emitting = true
	burst.amount = 28
	burst.lifetime = 1.4
	burst.explosiveness = 1.0
	burst.direction = Vector2(0, -1)
	burst.spread = 70.0
	burst.initial_velocity_min = 90.0
	burst.initial_velocity_max = 170.0
	burst.gravity = Vector2(0, 260)
	burst.scale_amount_min = 2.0
	burst.scale_amount_max = 4.0
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Palette.AMBER_LIGHT, Palette.SAGE_LIGHT, Palette.CLAY, Palette.CREAM])
	gradient.offsets = PackedFloat32Array([0.0, 0.33, 0.66, 1.0])
	gradient.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	burst.color_initial_ramp = gradient
	return burst
