class_name UiChecks
extends RefCounted
## Headless checks for the strip's scenes: window geometry, layout bounds, art and audio
## wiring, a still idle, and accessibility names. They drive the real Session autoload,
## which does not touch disk in a headless run, and put it back to idle afterwards.

const MAIN_SCENE: PackedScene = preload("res://scenes/boot/main.tscn")
const STAGE_SCENE: PackedScene = preload("res://scenes/stage/stage_view.tscn")
const CATALOG: Catalog = preload("res://data/catalog.tres")

var _tree: SceneTree
var _expect: Callable


func _init(tree: SceneTree, expect: Callable) -> void:
	_tree = tree
	_expect = expect


func run() -> void:
	_check_geometry()
	_check_dock_settings()
	_check_assets()
	await _check_poses_and_loop()
	await _check_layout()
	await _check_ticker()
	await _check_still_idle_and_service()
	await _check_reveal_audio_and_sleep()
	await _check_intro_once()
	await _check_accessibility()
	_reset_session()


func _ok(condition: bool, message: String) -> void:
	_expect.call(condition, message)


func _frames(count: int = 2) -> void:
	for _i in count:
		await _tree.process_frame


func _reset_session() -> void:
	Session.time_scale = 1.0
	Session.muted = false
	Session.abandon()


# --- Geometry --------------------------------------------------------------

func _check_geometry() -> void:
	var usable := Rect2i(0, 0, 1920, 1040)
	# HiDPI smoke test: cozy at scale 2 stays on the usable rect and lays out at 220 design pixels.
	var cozy_2 := DockGeometry.window_rect(usable, DockGeometry.EDGE_BOTTOM, DockGeometry.PRESET_COZY, false, 2.0)
	_ok(cozy_2 == Rect2i(0, 600, 1920, 440), "cozy at scale 2 rect %s" % cozy_2)
	_ok(DockGeometry.fits(cozy_2, usable), "cozy at scale 2 leaves the usable rect")
	_ok(DockGeometry.logical_size(cozy_2.size, 2.0) == Vector2i(960, 220), "cozy at scale 2 logical size")
	var focus_2 := DockGeometry.window_rect(usable, DockGeometry.EDGE_BOTTOM, DockGeometry.PRESET_COZY, true, 2.0)
	_ok(focus_2.size.y == 680 and DockGeometry.fits(focus_2, usable), "focus at scale 2 rect %s" % focus_2)
	# A short screen clamps instead of leaving the rect.
	var short := Rect2i(100, 40, 1280, 300)
	var clamped := DockGeometry.window_rect(short, DockGeometry.EDGE_BOTTOM, DockGeometry.PRESET_COZY, true, 2.0)
	_ok(DockGeometry.fits(clamped, short), "clamped focus rect %s" % clamped)
	# Left edge: usable height, the preset's long side, and focus height does not apply.
	var left_cozy := DockGeometry.window_rect(usable, DockGeometry.EDGE_LEFT, DockGeometry.PRESET_COZY, false, 1.0)
	_ok(left_cozy == Rect2i(0, 0, 220, 1040), "left cozy rect %s" % left_cozy)
	var left_compact := DockGeometry.window_rect(usable, DockGeometry.EDGE_LEFT, DockGeometry.PRESET_COMPACT, true, 1.0)
	_ok(left_compact == Rect2i(0, 0, 144, 1040), "left compact ignores focus %s" % left_compact)
	var offset_usable := Rect2i(1920, 30, 1600, 900)
	var left_offset := DockGeometry.window_rect(offset_usable, DockGeometry.EDGE_LEFT, DockGeometry.PRESET_COZY, false, 1.5)
	_ok(left_offset == Rect2i(1920, 30, 330, 900), "left on a second screen %s" % left_offset)
	var ticker := DockGeometry.window_rect(usable, DockGeometry.EDGE_BOTTOM, DockGeometry.PRESET_TICKER, false, 1.0)
	_ok(ticker == Rect2i(0, 976, 1920, 64), "ticker rest rect %s" % ticker)
	var ticker_open := DockGeometry.window_rect(usable, DockGeometry.EDGE_BOTTOM, DockGeometry.PRESET_TICKER, true, 1.0)
	_ok(ticker_open == Rect2i(0, 700, 1920, 340), "ticker open rect %s" % ticker_open)
	var left_ticker := DockGeometry.window_rect(usable, DockGeometry.EDGE_LEFT, DockGeometry.PRESET_TICKER, false, 1.0)
	_ok(left_ticker == Rect2i(0, 0, 144, 1040), "a left ticker is a compact column %s" % left_ticker)
	_ok(DockGeometry.is_ticker(DockGeometry.EDGE_BOTTOM, DockGeometry.PRESET_TICKER), "bottom ticker")
	_ok(not DockGeometry.is_ticker(DockGeometry.EDGE_LEFT, DockGeometry.PRESET_TICKER), "left is never a ticker")
	_ok(DockGeometry.nearest_step(1.3) == 1.25, "snap 1.3")
	_ok(DockGeometry.nearest_step(9.0) == 2.0, "snap 9")
	_ok(DockGeometry.nearest_step(0.0) == 1.0, "snap 0")


func _check_dock_settings() -> void:
	var edge := Dock.get_edge()
	var choice := Dock.get_scale_choice()
	var capture := Dock.is_excluded_from_capture()
	Dock.set_scale_choice("2.0")
	_ok(Dock.get_scale_choice() == "2.0", "scale choice 2.0 is %s" % Dock.get_scale_choice())
	Dock.set_scale_choice("1.25")
	_ok(Dock.get_scale_choice() == "1.25", "scale choice 1.25 is %s" % Dock.get_scale_choice())
	Dock.set_scale_choice(Dock.SCALE_MATCH)
	if Dock.has_match_scale():
		_ok(Dock.get_scale_choice() == Dock.SCALE_MATCH, "match screen was refused where offered")
	else:
		_ok(Dock.get_scale_choice() == "1.25", "match screen was accepted where it does nothing")
	Dock.set_scale_choice(choice)
	Dock.set_edge("middle")
	_ok(Dock.get_edge() == edge, "a bad edge was accepted")
	var os_name := OS.get_name()
	_ok(
		Dock.can_exclude_from_capture() == (os_name == "Windows" or os_name == "macOS"),
		"exclude from capture offered on %s" % os_name
	)
	if not Dock.can_exclude_from_capture():
		Dock.set_exclude_from_capture(true)
		_ok(not Dock.is_excluded_from_capture(), "exclude from capture stuck where the hint does nothing")
	Dock.set_exclude_from_capture(capture)


# --- Assets ----------------------------------------------------------------

func _check_assets() -> void:
	for driver in CATALOG.drivers:
		_ok(driver.portrait != null, "driver %s has no portrait" % driver.id)
	for car in CATALOG.cars:
		_ok(car.portrait != null, "car %s has no portrait" % car.id)
	for stage in CATALOG.stages_in_order():
		_ok(StageView.SURFACE_TEXTURES.has(stage.surface), "no art for the %s surface of %s" % [stage.surface, stage.id])
	for surface in StageView.SURFACE_TEXTURES:
		var layers: Dictionary = StageView.SURFACE_TEXTURES[surface]
		for layer in ["sky", "hills", "props", "ground", "road"]:
			_ok(layers.get(layer) is Texture2D, "%s has no %s layer" % [surface, layer])
	var master := AudioServer.get_bus_index("Master")
	_ok(master >= 0, "no Master bus")
	_ok(is_equal_approx(AudioServer.get_bus_volume_db(master), -18.0), "master volume %s" % AudioServer.get_bus_volume_db(master))
	var loop := load("res://audio/reveal_loop.wav") as AudioStreamWAV
	_ok(loop != null and loop.loop_mode == AudioStreamWAV.LOOP_FORWARD, "the reveal loop does not loop")
	_ok(load("res://audio/incident_stinger.wav") is AudioStreamWAV, "the stinger is missing")
	_ok(
		str(ProjectSettings.get_setting("audio/driver/driver", "")) != "Dummy",
		"audio driver was forced to Dummy"
	)
	_ok(StageView.pose_for_kind("slide") == &"slide", "slide pose")
	_ok(StageView.pose_for_kind("jump") == &"hop", "hop pose")
	_ok(StageView.pose_for_kind("hazard") == &"wobble", "hazard pose")
	_ok(StageView.pose_for_kind("straight") == &"wobble", "straight pose")


func _check_poses_and_loop() -> void:
	var view := STAGE_SCENE.instantiate() as StageView
	_tree.root.add_child(view)
	await _frames()
	var poses := view.get_node("%Poses") as AnimationPlayer
	_ok(poses.autoplay == "", "the pose player autoplays %s" % poses.autoplay)
	_ok(not poses.is_playing(), "a pose plays before any incident")
	for clip in ["slide", "hop", "wobble"]:
		_ok(poses.has_animation(clip), "missing %s clip" % clip)
		if poses.has_animation(clip):
			_ok(poses.get_animation(clip).loop_mode == Animation.LOOP_NONE, "%s clip loops" % clip)
	_ok(view.get_node("%Loop").playing, "the reveal loop did not start with the view")
	_ok(OS.low_processor_usage_mode_sleep_usec == StageView.REVEAL_SLEEP_USEC, "reveal sleep not lowered")
	view._play_pose("jump")
	_ok(poses.is_playing() and poses.current_animation == "hop", "a jump incident did not play hop")
	view._play_pose("slide")
	_ok(poses.current_animation == "slide", "a slide incident did not play slide")
	var loop_player := view.get_node("%Loop") as AudioStreamPlayer
	_tree.root.remove_child(view)
	_ok(not loop_player.playing, "the reveal loop kept playing after the view left the tree")
	_ok(OS.low_processor_usage_mode_sleep_usec == StageView.REST_SLEEP_USEC, "rest sleep not restored")
	view.free()


# --- Layout ----------------------------------------------------------------

func _check_layout() -> void:
	_reset_session()
	# A headless window keeps its size, so the strip lives in a SubViewport that does resize.
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 220)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_tree.root.add_child(viewport)
	var main := MAIN_SCENE.instantiate() as Control
	viewport.add_child(main)
	await _frames()
	var settings_button := main.get_node("%SettingsButton") as Button
	settings_button.pressed.emit()
	# Show the platform-only controls so the cluster is measured at its widest.
	main.get_node("%ExcludeCapture").visible = true
	main.get_node("%ScaleMatch").visible = true
	await _frames()
	var cases := [
		["bottom", Vector2i(1280, 220)],
		["bottom", Vector2i(1280, 144)],
		["bottom", Vector2i(1024, 144)],
		["left", Vector2i(220, 1000)],
		["left", Vector2i(144, 1000)],
	]
	var original_edge := Dock.get_edge()
	for case in cases:
		var edge: String = case[0]
		var window_size: Vector2i = case[1]
		Dock.set_edge(edge)
		viewport.size = window_size
		await _frames()
		var bounds := Rect2(Vector2.ZERO, Vector2(window_size))
		var label := "%s %s" % [edge, window_size]
		for node_name in ["QuitButton", "SettingsButton", "Mute", "EdgeBottom", "EdgeLeft", "Scale100", "Scale200", "ExcludeCapture", "ScaleMatch"]:
			var control := main.get_node("%" + node_name) as Control
			_ok(
				bounds.encloses(control.get_global_rect()),
				"%s leaves the window at %s: %s" % [node_name, label, control.get_global_rect()]
			)
		var panel := main.get_node("%SettingsPanel") as Control
		_ok(
			panel.get_combined_minimum_size().y <= panel.size.y + 1.0,
			"settings cluster overflows its panel at %s: %s > %s" % [label, panel.get_combined_minimum_size().y, panel.size.y]
		)
		var handle := main.get_node("%MouseDragHandle") as Control
		var handle_rect := handle.get_global_rect()
		if edge == "left":
			_ok(handle_rect.size.y > handle_rect.size.x, "the left handle is not vertical %s" % handle_rect)
			_ok(handle_rect.end.x > bounds.size.x * 0.75, "the left handle is not on the inner edge %s" % handle_rect)
		else:
			_ok(handle_rect.size.x > handle_rect.size.y, "the bottom handle is not horizontal %s" % handle_rect)
	Dock.set_edge(original_edge)
	_tree.root.remove_child(viewport)
	viewport.free()


# --- Ticker ----------------------------------------------------------------

func _check_ticker() -> void:
	_reset_session()
	var preset := Dock.get_preset()
	var edge := Dock.get_edge()
	# The layout check above leaves its settings panel open on the autoload.
	Dock.set_settings_open(false)
	Dock.set_panel_phase(false)
	Dock.set_edge(Dock.EDGE_BOTTOM)
	Dock.set_preset(Dock.PRESET_TICKER)
	# The panel stays shut behind the chip until the player opens it.
	Dock.set_panel_phase(true)
	_ok(not Dock.is_focus(), "a choice phase auto-expanded the ticker")
	Dock.set_panel_open(true)
	_ok(Dock.is_focus(), "opening the panel did not grow the window")
	Dock.set_panel_phase(false)
	_ok(not Dock.is_focus() and not Dock.is_panel_open(), "leaving the choice phase left the panel open")
	Dock.set_settings_open(true)
	_ok(Dock.is_focus(), "settings did not borrow the open height")
	Dock.set_settings_open(false)
	_ok(not Dock.is_focus(), "closing settings kept the ticker open")
	# Compact and cozy keep their old behavior: a choice phase grows the window at once.
	Dock.set_preset(Dock.PRESET_COZY)
	Dock.set_panel_phase(true)
	_ok(Dock.is_focus(), "cozy no longer grows on a choice phase")
	Dock.set_edge(Dock.EDGE_LEFT)
	Dock.set_preset(Dock.PRESET_TICKER)
	_ok(not Dock.is_ticker(), "a left-edge strip counted as a ticker")
	_ok(Dock.is_focus(), "a left-edge choice phase did not take focus")
	Dock.set_panel_phase(false)
	Dock.set_edge(Dock.EDGE_BOTTOM)

	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 64)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_tree.root.add_child(viewport)
	var main := MAIN_SCENE.instantiate() as Control
	viewport.add_child(main)
	await _frames()
	var rest := Rect2(Vector2.ZERO, Vector2(viewport.size))
	for node_name in ["SettingsButton", "MouseDragHandle"]:
		var control := main.get_node("%" + node_name) as Control
		_ok(rest.encloses(control.get_global_rect()), "%s leaves the ticker: %s" % [node_name, control.get_global_rect()])
	var row := main.find_child("Ticker", true, false) as Control
	_ok(row != null and rest.encloses(row.get_global_rect()), "the idle ticker row leaves the window")
	var start := _first_button(main, "Start championship")
	_ok(start != null and rest.encloses(start.get_global_rect()), "the Start button leaves the ticker")
	# Settings borrow the open height, so every control must fit the tall window.
	viewport.size = Vector2i(1280, 340)
	(main.get_node("%SettingsButton") as Button).pressed.emit()
	main.get_node("%ExcludeCapture").visible = true
	main.get_node("%ScaleMatch").visible = true
	await _frames()
	var open := Rect2(Vector2.ZERO, Vector2(viewport.size))
	for node_name in ["QuitButton", "SettingsButton", "Mute", "Ticker", "EdgeLeft", "Scale200", "ExcludeCapture", "ScaleMatch"]:
		var control := main.get_node("%" + node_name) as Control
		_ok(open.encloses(control.get_global_rect()), "%s leaves the open ticker: %s" % [node_name, control.get_global_rect()])
	var panel := main.get_node("%SettingsPanel") as Control
	_ok(panel.get_combined_minimum_size().y <= panel.size.y + 1.0, "ticker settings overflow their panel")
	_ok(not panel.get_global_rect().intersects(row.get_global_rect()) if is_instance_valid(row) else true, "settings cover the ticker row")
	(main.get_node("%SettingsButton") as Button).pressed.emit()
	# A draft waits behind the chip; the chip opens it, and a second press shuts it.
	Session.start_draft()
	await _frames(3)
	var chip := main.find_child("PanelChip", true, false) as Button
	_ok(chip != null, "the ticker shows no chip while a draft is pending")
	# The very first draft opens once as a hint, so shut it first when it is already open.
	if Dock.is_panel_open():
		chip.pressed.emit()
		await _frames(3)
	_ok(not Dock.is_focus() and main.find_child("DraftView", true, false) == null, "the draft opened by itself")
	(main.find_child("PanelChip", true, false) as Button).pressed.emit()
	await _frames(3)
	_ok(Dock.is_focus() and main.find_child("DraftView", true, false) != null, "the chip did not open the draft")
	(main.find_child("PanelChip", true, false) as Button).pressed.emit()
	await _frames(3)
	_ok(not Dock.is_focus() and main.find_child("DraftView", true, false) == null, "the chip did not close the draft")
	_reset_session()
	await _frames(2)
	_tree.root.remove_child(viewport)
	viewport.free()
	Dock.set_settings_open(false)
	Dock.set_panel_phase(false)
	Dock.set_preset(preset)
	Dock.set_edge(edge)


func _first_button(root: Node, text: String) -> Button:
	for node in root.find_children("*", "Button", true, false):
		if (node as Button).text == text:
			return node as Button
	return null


# --- Still picture ---------------------------------------------------------

## Idle and service sit still apart from the card pulse: nothing animates, loops, or plays.
func _check_still_idle_and_service() -> void:
	_reset_session()
	var main := MAIN_SCENE.instantiate() as Control
	_tree.root.add_child(main)
	await _frames(3)
	_ok(Session.phase() == Championship.PHASE_IDLE, "session is not idle")
	_audit_still(main, "idle", false)
	var hud := main.get_node("%HudStrip") as HudStrip
	_ok(hud._timer.is_stopped(), "the clock timer runs while idle")

	Session.time_scale = 1800.0
	Session.start_draft()
	var now := Time.get_unix_time_from_system()
	_ok(Session.confirm_draft("pip", "teapot", now, 1), "check draft was refused")
	await _frames(3)
	Session.advance(now + 1.2)
	await _frames(3)
	_ok(Session.phase() == Championship.PHASE_SERVICE, "expected service, got %s" % Session.phase())
	# The pulse is the only motion while a choice is open.
	_audit_still(main, "service with a choice open", true)
	var card_id := ""
	var offer := Session.championship.offer_for(Championship.PLAYER_ID)
	var ids: Array = offer.get("card_ids", [])
	if not ids.is_empty():
		card_id = str(ids[0])
	_ok(Session.choose_card(card_id), "check card was refused")
	var service := main.find_child("ServiceRoot", true, false)
	_ok(service != null, "no service view")
	var view := service.get_parent() as ServiceView
	view._apply_selection_visuals()
	view._sync_pulse()
	await _frames(2)
	_audit_still(main, "service after a pick", false)
	_ok(view.get_node_or_null("Park") is TextureRect, "the park is not an illustration")
	_ok(view.get_node("Park").texture != null, "the park has no texture")
	_ok(not main.find_child("Loop", true, false), "the reveal loop exists outside the reveal")
	main.get_parent().remove_child(main)
	main.free()
	_reset_session()


## Records every reason a canvas could keep redrawing. `pulse_allowed` permits the card pulse tween.
func _audit_still(root_node: Node, label: String, pulse_allowed: bool) -> void:
	var stack: Array[Node] = [root_node]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		if node is AnimationPlayer:
			var player := node as AnimationPlayer
			_ok(player.autoplay == "" and not player.is_playing(), "%s: %s animates" % [label, node.name])
		if node is AudioStreamPlayer:
			_ok(not (node as AudioStreamPlayer).playing, "%s: %s is playing" % [label, node.name])
		if node is GPUParticles2D:
			_ok(not (node as GPUParticles2D).emitting, "%s: %s emits" % [label, node.name])
		if node is CPUParticles2D:
			_ok(not (node as CPUParticles2D).emitting, "%s: %s emits" % [label, node.name])
		if node is CanvasItem:
			var item := node as CanvasItem
			if item.material is ShaderMaterial:
				var code := ((item.material as ShaderMaterial).shader.code) if (item.material as ShaderMaterial).shader != null else ""
				_ok(not code.contains("TIME"), "%s: %s reads TIME" % [label, node.name])
	var tweens := _tree.get_processed_tweens().size()
	if pulse_allowed:
		_ok(tweens <= 1, "%s: %s tweens are running" % [label, tweens])
	else:
		_ok(tweens == 0, "%s: %s tweens are running" % [label, tweens])


func _check_reveal_audio_and_sleep() -> void:
	_reset_session()
	var main := MAIN_SCENE.instantiate() as Control
	_tree.root.add_child(main)
	await _frames(3)
	Session.start_draft()
	var now := Time.get_unix_time_from_system()
	Session.confirm_draft("pip", "teapot", now, 1)
	await _frames(3)
	var loop := main.find_child("Loop", true, false) as AudioStreamPlayer
	_ok(loop != null and loop.playing, "no reveal loop during the reveal")
	_ok(OS.low_processor_usage_mode_sleep_usec == StageView.REVEAL_SLEEP_USEC, "reveal sleep is %s" % OS.low_processor_usage_mode_sleep_usec)
	var stinger := main.find_child("Stinger", true, false) as AudioStreamPlayer
	_ok(stinger != null and stinger.stream != null, "no incident stinger")
	# Mute is a bus switch: the loop keeps running, so unmuting is heard at once.
	Session.muted = true
	main.apply_mute()
	var master := AudioServer.get_bus_index("Master")
	_ok(AudioServer.is_bus_mute(master), "muting did not mute the bus")
	_ok(loop.playing, "muting stopped the loop")
	Session.muted = false
	main.apply_mute()
	_ok(not AudioServer.is_bus_mute(master), "unmuting left the bus muted")
	_ok(loop.playing, "the loop was not running when unmuted")
	Session.time_scale = 1800.0
	Session.abandon()
	await _frames(3)
	_ok(main.find_child("Loop", true, false) == null, "the loop outlived the reveal")
	_ok(OS.low_processor_usage_mode_sleep_usec == StageView.REST_SLEEP_USEC, "rest sleep not restored after the reveal")
	main.get_parent().remove_child(main)
	main.free()
	_reset_session()


func _check_intro_once() -> void:
	_reset_session()
	var was_seen := Dock.has_seen_intro()
	Dock._seen_intro = false
	var main := MAIN_SCENE.instantiate() as Control
	_tree.root.add_child(main)
	await _frames(3)
	_ok(main.find_child("Intro", true, false) != null, "first launch shows no intro")
	_ok(Dock.has_seen_intro(), "the intro was not marked seen")
	var intro := main.find_child("Intro", true, false) as Label
	if intro != null:
		_ok(intro.text.count("\n") == 2, "intro is not three lines: %s" % intro.text)
	# Leaving idle and coming back must not show it again.
	Session.start_draft()
	await _frames(3)
	Session.abandon()
	await _frames(3)
	_ok(main.find_child("Intro", true, false) == null, "the intro came back in the same run")
	_ok(main.find_child("Roster", true, false) != null, "idle shows no animals")
	Dock._seen_intro = was_seen
	main.get_parent().remove_child(main)
	main.free()
	_reset_session()


# --- Accessibility ---------------------------------------------------------

func _check_accessibility() -> void:
	_reset_session()
	var main := MAIN_SCENE.instantiate() as Control
	_tree.root.add_child(main)
	await _frames(3)
	for node_name in ["SettingsButton", "PauseButton", "QuitButton", "Mute"]:
		var control := main.get_node("%" + node_name) as Control
		_ok(control.accessibility_name != "", "%s has no accessibility name" % node_name)
	for node_name in ["SettingsButton", "PauseButton", "QuitButton"]:
		var control := main.get_node("%" + node_name) as Control
		_ok(control.accessibility_description != "", "%s has no accessibility description" % node_name)

	Session.start_draft()
	await _frames(3)
	var rows: Array[Button] = []
	for node in main.find_children("*", "Button", true, false):
		if node.has_meta("item_id"):
			rows.append(node as Button)
	_ok(rows.size() == 9, "draft rows %s" % rows.size())
	for row in rows:
		_ok(row.accessibility_name != "", "a draft row has no accessibility name")
		_ok(not row.text.begins_with("✓"), "a row starts selected")
	if not rows.is_empty():
		rows[0].button_pressed = true
		_ok(rows[0].text.begins_with("✓ "), "a selected row has no check mark: %s" % rows[0].text)
		_ok(rows[0].accessibility_description.begins_with("Selected"), "row description %s" % rows[0].accessibility_description)
		if rows.size() > 1 and rows[1].button_group == rows[0].button_group:
			rows[1].button_pressed = true
			_ok(not rows[0].text.begins_with("✓"), "a deselected row kept its check mark")

	Session.abandon()
	await _frames(2)
	Session.time_scale = 1800.0
	Session.start_draft()
	var now := Time.get_unix_time_from_system()
	Session.confirm_draft("pip", "teapot", now, 1)
	await _frames(2)
	Session.advance(now + 1.2)
	await _frames(3)
	var cards: Array[PanelContainer] = []
	for node in main.find_children("*", "PanelContainer", true, false):
		if node.has_meta("card_id"):
			cards.append(node as PanelContainer)
	_ok(cards.size() == 3, "service cards %s" % cards.size())
	var safe_cards := 0
	for card in cards:
		_ok(card.accessibility_name != "", "a card has no accessibility name")
		_ok(card.accessibility_description != "", "a card has no accessibility description")
		if bool(card.get_meta("safe", false)):
			safe_cards += 1
			_ok(card.find_child("Away", true, false).text.contains("step away"), "the safe card lost its step-away words")
	_ok(safe_cards == 1, "safe cards %s" % safe_cards)
	if not cards.is_empty():
		var chosen_id := str(cards[0].get_meta("card_id"))
		Session.choose_card(chosen_id)
		var view := cards[0].get_parent().get_parent().get_parent() as ServiceView
		view._apply_selection_visuals()
		var title := cards[0].find_child("Title", true, false) as Label
		_ok(title.text.begins_with("✓ "), "the chosen card has no check mark: %s" % title.text)
	main.get_parent().remove_child(main)
	main.free()
	_reset_session()
