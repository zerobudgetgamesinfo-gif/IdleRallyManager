class_name Palette
extends RefCounted
## One shared palette. Views read colors from here instead of declaring their own.

const INK := Color(0.122, 0.094, 0.071, 1.0)
const BROWN_DEEP := Color(0.137, 0.114, 0.090, 1.0)
const BROWN := Color(0.176, 0.149, 0.118, 1.0)
const BROWN_LIGHT := Color(0.255, 0.216, 0.171, 1.0)
const CARD := Color(0.22, 0.20, 0.17, 0.92)
const CARD_HOVER := Color(0.29, 0.255, 0.21, 0.96)
const CREAM := Color(0.973, 0.941, 0.878, 1.0)
const CREAM_MUTED := Color(0.973, 0.941, 0.878, 0.72)
const AMBER := Color(0.855, 0.624, 0.29, 1.0)
const AMBER_LIGHT := Color(0.949, 0.757, 0.447, 1.0)
const AMBER_DEEP := Color(0.62, 0.42, 0.16, 1.0)
const SAGE := Color(0.42, 0.48, 0.34, 1.0)
const SAGE_LIGHT := Color(0.52, 0.59, 0.42, 1.0)
const CLAY := Color(0.72, 0.38, 0.28, 1.0)
const HIGHLIGHT := Color(1.0, 0.96, 0.88, 0.14)
const SHADOW := Color(0.0, 0.0, 0.0, 0.35)

const SURFACE_ACCENT := {
	"gravel": Color(0.78, 0.62, 0.36, 1.0),
	"tarmac": Color(0.45, 0.55, 0.66, 1.0),
	"snow": Color(0.80, 0.88, 0.94, 1.0),
}
