extends Node
## Entry point for the scene checks. Runs inside a normal scene run so the Session and Dock
## autoloads exist, then quits with a non-zero code when a check failed.
## godot --headless --path . res://sim/checks/ui_runner.tscn

const TIMEOUT_SECONDS := 180.0

var _failures: PackedStringArray = []


func _ready() -> void:
	get_tree().create_timer(TIMEOUT_SECONDS).timeout.connect(_on_timeout)
	await get_tree().process_frame
	var checks := UiChecks.new(get_tree(), Callable(self, "_expect"))
	await checks.run()
	if _failures.is_empty():
		print("Scene checks passed.")
		get_tree().quit(0)
		return
	for failure in _failures:
		print("FAIL: %s" % failure)
	get_tree().quit(1)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)
	push_error(message)


func _on_timeout() -> void:
	print("FAIL: scene checks timed out")
	get_tree().quit(1)
