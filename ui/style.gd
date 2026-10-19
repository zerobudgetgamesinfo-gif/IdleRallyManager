class_name Style
extends RefCounted
## StyleBox factories shared by the phase views and the theme.

const RADIUS := 8
const CARD_RADIUS := 8


static func box(fill: Color, radius: int, border: Color = Color(0, 0, 0, 0), border_width := 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.set_corner_radius_all(radius)
	style.set_border_width_all(border_width)
	style.border_color = border
	style.set_content_margin_all(6)
	return style


## A raised surface: lighter top edge, darker bottom edge, soft shadow.
static func raised(fill: Color, radius: int, border: Color, shadow := 4) -> StyleBoxFlat:
	var style := box(fill, radius, border, 1)
	style.border_width_top = 2
	style.border_width_bottom = 1
	style.shadow_color = Palette.SHADOW
	style.shadow_size = shadow
	style.shadow_offset = Vector2(0, 2)
	return style


static func card(selected: bool, hover := false) -> StyleBoxFlat:
	var fill := Palette.SAGE if selected else (Palette.CARD_HOVER if hover else Palette.CARD)
	var border := Palette.AMBER_LIGHT if selected else Palette.BROWN_LIGHT
	var style := raised(fill, CARD_RADIUS, border, 3)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style


static func chip(fill: Color = Palette.BROWN_DEEP) -> StyleBoxFlat:
	var style := box(fill, 10, Palette.BROWN_LIGHT, 1)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	return style


static func backdrop(alpha := 0.78) -> StyleBoxFlat:
	var style := box(Color(Palette.BROWN.r, Palette.BROWN.g, Palette.BROWN.b, alpha), 6)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	return style


## Vertical two-tone gradient used as the strip's sheen. No animation, so it is safe in idle.
static func sheen() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 0.92, 0.76, 0.10))
	gradient.set_color(1, Color(0.0, 0.0, 0.0, 0.22))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0.5, 0.0)
	texture.fill_to = Vector2(0.5, 1.0)
	texture.width = 4
	texture.height = 64
	return texture
