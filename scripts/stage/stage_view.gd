class_name StageView
extends Control
## Side view of the open reveal. Positions are applied from RevealPlayback.
## The strip frees this node when the phase leaves stage_reveal, which stops _process.
## While it is in the tree the redraw sleep is about 30 fps. Leaving restores the idle sleep.

const REVEAL_SLEEP_USEC := 33333
const REST_SLEEP_USEC := 100000

const SKY_SPEED := 72.0
const GROUND_SPEED := 220.0
const ROAD_SPEED := 320.0
const GAP_PX_PER_SEC := 1.5
const PLAYER_X_START := 0.24
const PLAYER_X_END := 0.40
const POSE_SEC := 2.4
const RIVAL_LIMIT := 7
const TICK_SIZE := Vector2(4, 16)
const MARK_CLOUD_GAP := 260.0
const MARK_POST_GAP := 170.0
const MARK_DASH_GAP := 64.0

const SURFACE_SKY := {
	"gravel": Color(0.38, 0.48, 0.60),
	"tarmac": Color(0.42, 0.52, 0.62),
	"snow": Color(0.58, 0.66, 0.74),
}
const SURFACE_GROUND := {
	"gravel": Color(0.76, 0.61, 0.32),
	"tarmac": Color(0.45, 0.51, 0.58),
	"snow": Color(0.86, 0.89, 0.92),
}
const SURFACE_ROAD := {
	"gravel": Color(0.40, 0.32, 0.20),
	"tarmac": Color(0.22, 0.24, 0.28),
	"snow": Color(0.68, 0.74, 0.80),
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
var _marks_key := ""
var _fired: Dictionary = {}
var _pose_tween: Tween
var _pose_paused := false
var _ticks: Array[ColorRect] = []
var _clouds: Array[ColorRect] = []
var _posts: Array[ColorRect] = []
var _dashes: Array[ColorRect] = []

@onready var _sky: ColorRect = %Sky
@onready var _ground: ColorRect = %Ground
@onready var _road: ColorRect = %Road
@onready var _rivals: Node2D = %Rivals
@onready var _player: Node2D = %Player
@onready var _pose: Node2D = %Pose


func _enter_tree() -> void:
	OS.low_processor_usage_mode_sleep_usec = REVEAL_SLEEP_USEC


func _exit_tree() -> void:
	var tween := _pose_tween
	_pose_tween = null
	_pose_paused = false
	if tween != null and tween.is_valid():
		tween.kill()
	OS.low_processor_usage_mode_sleep_usec = REST_SLEEP_USEC


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ticks()


func _process(_delta: float) -> void:
	var f := _fraction()
	_advance_fraction(f)
	_sync_pose_pause(_championship_paused())
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


func _play_pose(kind: String) -> void:
	_clear_pose()
	if _pose == null:
		return
	var span := POSE_SEC / maxf(Session.time_scale, 0.001)
	var tween := create_tween()
	_pose_tween = tween
	_pose_paused = false
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.finished.connect(_on_pose_finished.bind(tween), CONNECT_ONE_SHOT)
	var offset := Vector2.ZERO
	var angle := 0.0
	match kind:
		"slide":
			offset = Vector2(0.0, 10.0)
			angle = deg_to_rad(-18.0)
		"jump":
			offset = Vector2(0.0, -22.0)
		"hazard":
			angle = deg_to_rad(18.0)
		_:
			offset = Vector2(14.0, 0.0)
	if not is_zero_approx(angle):
		tween.tween_property(_pose, "rotation", angle, span * 0.35)
	if offset != Vector2.ZERO:
		if is_zero_approx(angle):
			tween.tween_property(_pose, "position", offset, span * 0.35)
		else:
			tween.parallel().tween_property(_pose, "position", offset, span * 0.35)
	tween.chain().tween_property(_pose, "rotation", 0.0, span * 0.65)
	tween.parallel().tween_property(_pose, "position", Vector2.ZERO, span * 0.65)


func _on_pose_finished(tween: Tween) -> void:
	if tween != _pose_tween:
		return
	_pose_tween = null
	_pose_paused = false
	if is_instance_valid(_pose):
		_pose.position = Vector2.ZERO
		_pose.rotation = 0.0


func _clear_pose() -> void:
	var tween := _pose_tween
	_pose_tween = null
	_pose_paused = false
	if tween != null and tween.is_valid():
		tween.kill()
	if is_instance_valid(_pose):
		_pose.position = Vector2.ZERO
		_pose.rotation = 0.0


func _sync_pose_pause(paused: bool) -> void:
	if _pose_tween == null or paused == _pose_paused:
		return
	_pose_paused = paused
	if paused:
		_pose_tween.pause()
	else:
		_pose_tween.play()


func _draw_frame(f: float, view_size: Vector2, show_rivals: bool) -> void:
	var surface := _apply_surface()
	var road_y := clampf(view_size.y * 0.68, 24.0, maxf(24.0, view_size.y - 8.0))
	_place_layer(_sky, -f * SKY_SPEED, 0.0, view_size.x + SKY_SPEED, road_y + 4.0)
	_place_layer(_ground, -f * GROUND_SPEED, road_y - 4.0, view_size.x + GROUND_SPEED, view_size.y - (road_y - 4.0))
	_place_layer(_road, -f * ROAD_SPEED, road_y - 3.0, view_size.x + ROAD_SPEED, 6.0)
	_sync_marks(view_size, surface)
	var player_x := lerpf(view_size.x * PLAYER_X_START, view_size.x * PLAYER_X_END, f)
	player_x = clampf(player_x, 28.0, maxf(28.0, view_size.x - 64.0))
	_player.position = Vector2(player_x, road_y)
	_place_rivals(f, player_x, road_y, show_rivals)


func _place_layer(layer: ColorRect, x: float, y: float, width: float, height: float) -> void:
	layer.position = Vector2(x, y)
	layer.size = Vector2(maxf(width, 1.0), maxf(height, 1.0))


func _sync_marks(view_size: Vector2, surface: String) -> void:
	var key := "%d|%d|%s" % [int(view_size.x), int(view_size.y), surface]
	if key == _marks_key:
		return
	_marks_key = key
	var sky := SURFACE_SKY[surface] as Color
	var ground := SURFACE_GROUND[surface] as Color
	var road := SURFACE_ROAD[surface] as Color
	_layout_marks(
		_clouds,
		_sky,
		_mark_count(view_size.x + SKY_SPEED, MARK_CLOUD_GAP),
		sky.lightened(0.16),
		Vector2(78.0, 14.0),
		view_size.x + SKY_SPEED,
		MARK_CLOUD_GAP,
		8.0,
		true
	)
	_layout_marks(
		_posts,
		_ground,
		_mark_count(view_size.x + GROUND_SPEED, MARK_POST_GAP),
		ground.darkened(0.18),
		Vector2(12.0, 14.0),
		view_size.x + GROUND_SPEED,
		MARK_POST_GAP,
		12.0,
		false
	)
	_layout_marks(
		_dashes,
		_road,
		_mark_count(view_size.x + ROAD_SPEED, MARK_DASH_GAP),
		road.lightened(0.22),
		Vector2(28.0, 3.0),
		view_size.x + ROAD_SPEED,
		MARK_DASH_GAP,
		1.5,
		false
	)


func _mark_count(span: float, gap: float) -> int:
	return maxi(2, ceili(span / maxf(gap, 1.0)))


func _layout_marks(
	pool: Array[ColorRect],
	parent: Node,
	count: int,
	color: Color,
	mark_size: Vector2,
	span: float,
	gap: float,
	y: float,
	stagger: bool
) -> void:
	while pool.size() < count:
		var mark := ColorRect.new()
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(mark)
		pool.append(mark)
	while pool.size() > count:
		var extra := pool.pop_back() as ColorRect
		parent.remove_child(extra)
		extra.free()
	var step := maxf(gap, 1.0)
	if float(count) > 1.0 and span > step:
		step = span / float(count)
	for index in pool.size():
		var mark := pool[index]
		mark.color = color
		mark.size = mark_size
		var mark_y := y
		if stagger:
			mark_y = y + float(index % 2) * 12.0
		mark.position = Vector2(step * float(index), mark_y)


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
		if rival_index >= _ticks.size():
			break
		var tick := _ticks[rival_index]
		rival_index += 1
		var dx := (player_time - float(row.get("time", 0.0))) * GAP_PX_PER_SEC
		tick.visible = true
		tick.position = Vector2(player_x + dx - TICK_SIZE.x * 0.5, road_y - TICK_SIZE.y)
	for index in range(rival_index, _ticks.size()):
		_ticks[index].visible = false


func _build_ticks() -> void:
	for index in RIVAL_LIMIT:
		var tick := ColorRect.new()
		tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tick.color = RIVAL_COLORS[index]
		tick.size = TICK_SIZE
		tick.visible = false
		_rivals.add_child(tick)
		_ticks.append(tick)


func _apply_surface() -> String:
	var stage_id := _current_stage_id()
	var surface := _surface_for_stage(stage_id)
	if stage_id == _drawn_stage_id and _marks_key != "":
		return surface
	_sky.color = SURFACE_SKY[surface]
	_ground.color = SURFACE_GROUND[surface]
	_road.color = SURFACE_ROAD[surface]
	return surface


func _surface_for_stage(stage_id: String) -> String:
	var stage := Session.CATALOG.stage(stage_id)
	if stage != null and SURFACE_GROUND.has(stage.surface):
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
