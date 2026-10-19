class_name StageView
extends Control
## Side view of the open reveal. Positions are applied from RevealPlayback.
## The strip frees this node when the phase leaves stage_reveal, which stops _process.
## While it is in the tree the redraw sleep is about 30 fps and the reveal loop plays.
## Leaving restores the idle sleep and stops the loop.
##
## Layers are tiled SVG textures, one palette per surface. Poses are short
## AnimationPlayer clips (slide, hop, wobble) fired once by the crossing logic.

const REVEAL_SLEEP_USEC := 33333
const REST_SLEEP_USEC := 100000

const SKY_SPEED := 72.0
const HILLS_SPEED := 130.0
const GROUND_SPEED := 220.0
const ROAD_SPEED := 320.0
const FORE_SPEED := 420.0
const FORE_HEIGHT := 20.0
const FORE_MIN_VIEW := 72.0
const GAP_PX_PER_SEC := 1.5
const PLAYER_X_START := 0.24
const PLAYER_X_END := 0.40
const POSE_SEC := 2.4
const RIVAL_LIMIT := 7
const RIVAL_SIZE := Vector2(26, 14)
const HILLS_HEIGHT := 40.0
const PROPS_HEIGHT := 44.0
const GROUND_LIP := 8.0
const ROAD_TOP := 6.0
const ROAD_HEIGHT := 16.0

const POSE_SLIDE := &"slide"
const POSE_HOP := &"hop"
const POSE_WOBBLE := &"wobble"

const RIVAL_TEXTURE: Texture2D = preload("res://scenes/stage/art/car_rival.svg")
const SHADOW_TEXTURE: Texture2D = preload("res://scenes/stage/art/car_shadow.svg")
const SURFACE_TEXTURES := {
	"gravel": {
		"sky": preload("res://scenes/stage/art/sky_gravel.svg"),
		"hills": preload("res://scenes/stage/art/hills_gravel.svg"),
		"props": preload("res://scenes/stage/art/props_gravel.svg"),
		"ground": preload("res://scenes/stage/art/ground_gravel.svg"),
		"road": preload("res://scenes/stage/art/road_gravel.svg"),
		"fore": preload("res://scenes/stage/art/fore_gravel.svg"),
	},
	"tarmac": {
		"sky": preload("res://scenes/stage/art/sky_tarmac.svg"),
		"hills": preload("res://scenes/stage/art/hills_tarmac.svg"),
		"props": preload("res://scenes/stage/art/props_tarmac.svg"),
		"ground": preload("res://scenes/stage/art/ground_tarmac.svg"),
		"road": preload("res://scenes/stage/art/road_tarmac.svg"),
		"fore": preload("res://scenes/stage/art/fore_tarmac.svg"),
	},
	"snow": {
		"sky": preload("res://scenes/stage/art/sky_snow.svg"),
		"hills": preload("res://scenes/stage/art/hills_snow.svg"),
		"props": preload("res://scenes/stage/art/props_snow.svg"),
		"ground": preload("res://scenes/stage/art/ground_snow.svg"),
		"road": preload("res://scenes/stage/art/road_snow.svg"),
		"fore": preload("res://scenes/stage/art/fore_snow.svg"),
	},
}
const RIVAL_COLORS: Array[Color] = [
	Color(0.29, 0.45, 0.62),
	Color(0.35, 0.55, 0.38),
	Color(0.62, 0.45, 0.28),
	Color(0.48, 0.36, 0.58),
	Color(0.55, 0.32, 0.38),
	Color(0.32, 0.48, 0.52),
	Color(0.50, 0.48, 0.30),
]

var clock: Callable = Callable()

var _previous_f := -1.0
var _drawn_f := -1.0
var _drawn_size := Vector2(-1.0, -1.0)
var _drawn_rivals := false
var _drawn_stage_id := ""
var _surface := ""
var _fired: Dictionary = {}
var _pose_active := false
var _pose_paused := false
var _loop_paused := false
var _rivals_sprites: Array[Sprite2D] = []

@onready var _sky: TextureRect = %Sky
@onready var _hills: TextureRect = %Hills
@onready var _props: TextureRect = %Props
@onready var _ground: TextureRect = %Ground
@onready var _road: TextureRect = %Road
@onready var _fore: TextureRect = %Fore
@onready var _rivals: Node2D = %Rivals
@onready var _player: Node2D = %Player
@onready var _pose: Node2D = %Pose
@onready var _car: Sprite2D = %Car
@onready var _poses: AnimationPlayer = %Poses
@onready var _loop: AudioStreamPlayer = %Loop
@onready var _stinger: AudioStreamPlayer = %Stinger


func _enter_tree() -> void:
	OS.low_processor_usage_mode_sleep_usec = REVEAL_SLEEP_USEC


func _exit_tree() -> void:
	_pose_active = false
	_pose_paused = false
	if is_instance_valid(_loop):
		_loop.stop()
	if is_instance_valid(_poses):
		_poses.stop()
	OS.low_processor_usage_mode_sleep_usec = REST_SLEEP_USEC


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_player_car()
	_add_shadow()
	_build_rivals()
	_build_pose_clips()
	_poses.animation_finished.connect(_on_pose_finished)
	_loop.play()


## A soft ellipse under the car. It stays on the road when the pose hops.
func _add_shadow() -> void:
	var shadow := Sprite2D.new()
	shadow.name = "Shadow"
	shadow.texture = SHADOW_TEXTURE
	shadow.centered = false
	shadow.position = Vector2(0.0, -6.0)
	shadow.scale = Vector2(1.7, 1.0)
	_player.add_child(shadow)
	_player.move_child(shadow, 0)


## The drafted car's portrait stands in for the player; no championship leaves it blank.
func _apply_player_car() -> void:
	var champ := Session.championship
	var player := champ.player_entry() if champ != null else null
	var drafted := Session.CATALOG.car(player.car_id) if player != null else null
	_car.texture = drafted.portrait if drafted != null else null


func _process(_delta: float) -> void:
	var f := _fraction()
	_advance_fraction(f)
	var paused := _championship_paused()
	_sync_pose_pause(paused)
	_sync_loop_pause(paused)
	var view_size := size
	if view_size.x < 2.0 or view_size.y < 2.0:
		return
	var show_rivals := _show_rivals()
	if (
		is_equal_approx(f, _drawn_f)
		and view_size.is_equal_approx(_drawn_size)
		and show_rivals == _drawn_rivals
		and _current_stage_id() == _drawn_stage_id
	):
		return
	_draw_frame(f, view_size, show_rivals)
	_drawn_f = f
	_drawn_size = view_size
	_drawn_rivals = show_rivals
	_drawn_stage_id = _current_stage_id()


func _fraction() -> float:
	if Session.phase() != Championship.PHASE_STAGE_REVEAL:
		if _previous_f >= 0.0:
			return _previous_f
		return 0.0
	var now := Time.get_unix_time_from_system()
	if clock.is_valid():
		now = float(clock.call())
	return RevealPlayback.fraction_from_remaining(Session.remaining(now))


func _advance_fraction(f: float) -> void:
	if _previous_f < 0.0:
		_previous_f = f
		return
	if f >= _previous_f:
		_cross_incidents(_previous_f, f)
	_previous_f = f


func _cross_incidents(previous: float, f: float) -> void:
	var incidents := _player_incidents()
	for index in incidents.size():
		var incident: Dictionary = incidents[index]
		var t_norm := float(incident.get("t_norm", 0.0))
		if previous >= t_norm or f < t_norm or _fired.has(index):
			continue
		_fired[index] = true
		var kind := str(incident.get("kind", ""))
		print("StageView: crossed %s at t_norm %.2f" % [kind, t_norm])
		_play_pose(kind)
		_stinger.play()


## Slide and hop match their incident kinds. A straight or a hazard is a wobble.
static func pose_for_kind(kind: String) -> StringName:
	match kind:
		"slide":
			return POSE_SLIDE
		"jump":
			return POSE_HOP
		_:
			return POSE_WOBBLE


func _play_pose(kind: String) -> void:
	_clear_pose()
	if _poses == null:
		return
	# The clip is POSE_SEC long at time_scale 1. A debug scale plays it faster.
	_poses.speed_scale = maxf(Session.time_scale, 0.001)
	_poses.play(pose_for_kind(kind))
	_pose_active = true
	if _pose_paused:
		_poses.pause()


func _on_pose_finished(_clip: StringName) -> void:
	_pose_active = false
	_pose_paused = false
	_reset_pose()


func _clear_pose() -> void:
	_pose_active = false
	if is_instance_valid(_poses):
		_poses.stop()
	_reset_pose()


func _reset_pose() -> void:
	if is_instance_valid(_pose):
		_pose.position = Vector2.ZERO
		_pose.rotation = 0.0


func _sync_pose_pause(paused: bool) -> void:
	if not _pose_active or paused == _pose_paused:
		return
	_pose_paused = paused
	if paused:
		_poses.pause()
	else:
		_poses.play()


func _sync_loop_pause(paused: bool) -> void:
	if paused == _loop_paused:
		return
	_loop_paused = paused
	_loop.stream_paused = paused


## Clips are built here so the tracks stay next to the pose offsets. None loops, and
## the player never sets an autoplay clip.
func _build_pose_clips() -> void:
	var library := AnimationLibrary.new()
	library.add_animation(POSE_SLIDE, _clip(
		[0.0, 0.35, 0.7, 1.0],
		[Vector2(0, 0), Vector2(12, 0), Vector2(8, 0), Vector2(0, 0)],
		[0.0, deg_to_rad(-16.0), deg_to_rad(7.0), 0.0]
	))
	library.add_animation(POSE_HOP, _clip(
		[0.0, 0.35, 0.6, 0.75, 1.0],
		[Vector2(0, 0), Vector2(0, -22), Vector2(0, 0), Vector2(0, -5), Vector2(0, 0)],
		[0.0, deg_to_rad(-6.0), deg_to_rad(3.0), 0.0, 0.0]
	))
	library.add_animation(POSE_WOBBLE, _clip(
		[0.0, 0.2, 0.4, 0.6, 0.8, 1.0],
		[Vector2(0, 0), Vector2(0, -2), Vector2(0, 0), Vector2(0, -1), Vector2(0, 0), Vector2(0, 0)],
		[0.0, deg_to_rad(10.0), deg_to_rad(-9.0), deg_to_rad(6.0), deg_to_rad(-3.0), 0.0]
	))
	_poses.add_animation_library("", library)


## Key times are fractions of POSE_SEC.
func _clip(fractions: Array, offsets: Array, angles: Array) -> Animation:
	var animation := Animation.new()
	animation.length = POSE_SEC
	animation.loop_mode = Animation.LOOP_NONE
	var move := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(move, NodePath("Player/Pose:position"))
	animation.track_set_interpolation_type(move, Animation.INTERPOLATION_CUBIC)
	var turn := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(turn, NodePath("Player/Pose:rotation"))
	animation.track_set_interpolation_type(turn, Animation.INTERPOLATION_CUBIC)
	for index in fractions.size():
		var time := float(fractions[index]) * POSE_SEC
		animation.track_insert_key(move, time, offsets[index])
		animation.track_insert_key(turn, time, angles[index])
	return animation


func _draw_frame(f: float, view_size: Vector2, show_rivals: bool) -> void:
	_apply_surface()
	var road_y := clampf(view_size.y * 0.68, 24.0, maxf(24.0, view_size.y - 8.0))
	_place_layer(_sky, -f * SKY_SPEED, 0.0, view_size.x + SKY_SPEED, road_y + 4.0)
	_place_layer(_hills, -f * HILLS_SPEED, road_y - HILLS_HEIGHT, view_size.x + HILLS_SPEED, HILLS_HEIGHT)
	_place_layer(
		_props, -f * GROUND_SPEED, road_y - GROUND_LIP + 2.0 - PROPS_HEIGHT,
		view_size.x + GROUND_SPEED, PROPS_HEIGHT
	)
	_place_layer(
		_ground, -f * GROUND_SPEED, road_y - GROUND_LIP,
		view_size.x + GROUND_SPEED, view_size.y - (road_y - GROUND_LIP)
	)
	_place_layer(_road, -f * ROAD_SPEED, road_y - ROAD_TOP, view_size.x + ROAD_SPEED, ROAD_HEIGHT)
	# The foreground sits in front of the car at the bottom edge, only where the view is tall enough.
	_fore.visible = view_size.y >= FORE_MIN_VIEW
	_place_layer(_fore, -f * FORE_SPEED, view_size.y - FORE_HEIGHT, view_size.x + FORE_SPEED, FORE_HEIGHT)
	var player_x := lerpf(view_size.x * PLAYER_X_START, view_size.x * PLAYER_X_END, f)
	player_x = clampf(player_x, 36.0, maxf(36.0, view_size.x - 72.0))
	_player.position = Vector2(player_x, road_y)
	_place_rivals(f, player_x, road_y, show_rivals)


func _place_layer(layer: TextureRect, x: float, y: float, width: float, height: float) -> void:
	layer.position = Vector2(x, y)
	layer.size = Vector2(maxf(width, 1.0), maxf(height, 1.0))


func _place_rivals(f: float, player_x: float, road_y: float, show_rivals: bool) -> void:
	_rivals.visible = show_rivals
	if not show_rivals:
		return
	var ranked := RevealPlayback.sample(_playback_rows(), f)
	var player_time := 0.0
	for row in ranked:
		if str(row.get("entry_id", "")) == Championship.PLAYER_ID:
			player_time = float(row.get("time", 0.0))
			break
	var rival_index := 0
	for row in ranked:
		if str(row.get("entry_id", "")) == Championship.PLAYER_ID:
			continue
		if rival_index >= _rivals_sprites.size():
			break
		var marker := _rivals_sprites[rival_index]
		rival_index += 1
		var dx := (player_time - float(row.get("time", 0.0))) * GAP_PX_PER_SEC
		marker.visible = true
		marker.position = Vector2(player_x + dx - RIVAL_SIZE.x * 0.5, road_y - RIVAL_SIZE.y)
	for index in range(rival_index, _rivals_sprites.size()):
		_rivals_sprites[index].visible = false


func _build_rivals() -> void:
	for index in RIVAL_LIMIT:
		var marker := Sprite2D.new()
		marker.texture = RIVAL_TEXTURE
		marker.centered = false
		marker.modulate = RIVAL_COLORS[index]
		marker.visible = false
		_rivals.add_child(marker)
		_rivals_sprites.append(marker)


func _apply_surface() -> void:
	var surface := _surface_for_stage(_current_stage_id())
	if surface == _surface:
		return
	_surface = surface
	var textures: Dictionary = SURFACE_TEXTURES[surface]
	_sky.texture = textures["sky"]
	_hills.texture = textures["hills"]
	_props.texture = textures["props"]
	_ground.texture = textures["ground"]
	_road.texture = textures["road"]
	_fore.texture = textures["fore"]


func _surface_for_stage(stage_id: String) -> String:
	var stage := Session.CATALOG.stage(stage_id)
	if stage != null and SURFACE_TEXTURES.has(stage.surface):
		return stage.surface
	return "gravel"


func _current_stage_id() -> String:
	var champ := Session.championship
	if champ == null:
		return ""
	var stage := Session.CATALOG.stage_at(champ.stage_index)
	if stage == null:
		return ""
	return stage.id


func _playback_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var champ := Session.championship
	if champ == null:
		return rows
	for entry in champ.entries:
		var result := champ.stage_result(entry.id)
		if result == null:
			continue
		rows.append(RevealPlayback.row_from_result(entry.id, result))
	return rows


func _player_incidents() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var champ := Session.championship
	if champ == null:
		return found
	var result := champ.stage_result(Championship.PLAYER_ID)
	if result == null:
		return found
	for incident in result.incidents:
		found.append(incident)
	return found


## Compact is a 144 px strip and the ticks clip the HUD line. Cozy shows them.
func _show_rivals() -> bool:
	if Dock.get_preset() != Dock.PRESET_COZY:
		return false
	return size.y >= 72.0


func _championship_paused() -> bool:
	var champ := Session.championship
	return champ != null and champ.pause_started_unix != null
