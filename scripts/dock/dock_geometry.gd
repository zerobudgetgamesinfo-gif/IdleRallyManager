class_name DockGeometry
extends RefCounted
## Pure window geometry for the strip. No DisplayServer reads, so a headless check can run it.
##
## Bottom edge: full usable width, height from the preset (or the focus height).
## Left edge: full usable height, width is the preset's long side (144 or 220). Focus height does not apply.
## Every pixel size is the design size times the content scale.

const EDGE_BOTTOM := "bottom"
const EDGE_LEFT := "left"

const PRESET_COMPACT := "compact"
const PRESET_COZY := "cozy"
const SIZE_COMPACT := 144
const SIZE_COZY := 220
const SIZE_FOCUS := 340

const SCALE_MATCH := "match"
const SCALE_STEPS: Array[float] = [1.0, 1.25, 1.5, 2.0]


static func preset_size(preset: String) -> int:
	if preset == PRESET_COMPACT:
		return SIZE_COMPACT
	return SIZE_COZY


## The strip's rectangle in desktop pixels.
static func window_rect(usable: Rect2i, edge: String, preset: String, focus: bool, scale: float) -> Rect2i:
	var factor := maxf(scale, 0.1)
	if edge == EDGE_LEFT:
		var width := mini(maxi(1, roundi(float(preset_size(preset)) * factor)), maxi(usable.size.x, 1))
		return Rect2i(usable.position, Vector2i(width, maxi(usable.size.y, 1)))
	var base := SIZE_FOCUS if focus else preset_size(preset)
	var height := mini(maxi(1, roundi(float(base) * factor)), maxi(usable.size.y, 1))
	return Rect2i(
		Vector2i(usable.position.x, usable.position.y + usable.size.y - height),
		Vector2i(maxi(usable.size.x, 1), height)
	)


## The design-pixel size the UI lays out in (the window's content_scale_size).
static func logical_size(pixel_size: Vector2i, scale: float) -> Vector2i:
	var factor := maxf(scale, 0.1)
	return Vector2i(
		maxi(1, roundi(float(pixel_size.x) / factor)),
		maxi(1, roundi(float(pixel_size.y) / factor))
	)


## True when the whole rectangle sits on the usable rect.
static func fits(rect: Rect2i, usable: Rect2i) -> bool:
	return usable.encloses(rect)


## Snap a stored number to the nearest offered scale step.
static func nearest_step(value: float) -> float:
	var best := SCALE_STEPS[0]
	for step in SCALE_STEPS:
		if absf(step - value) < absf(best - value):
			best = step
	return best
