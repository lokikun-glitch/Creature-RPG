extends Node
## Entry point for every test process (the main suite and each relaunch stage).
##
## The real tests live in another script that this runner loads at runtime, so a parse error in
## them can't leave Godot idling on the title screen: if the script doesn't compile, the process
## prints a FAIL line and exits with code 100. A global timeout turns any hang into exit code 99
## and names the section that was running.
##
## User arguments (after `--`):
##   --test-script=<path>    script to run (default: res://tests/smoke_test.gd)
##   --test-timeout=<secs>   game-time limit for the whole process (default: 3600)

const DEFAULT_SCRIPT := "res://tests/smoke_test.gd"
const DEFAULT_TIMEOUT := 3600.0
const EXIT_LOAD_FAILED := 100
const EXIT_TIMEOUT := 99

var _test: Node
var _timeout := DEFAULT_TIMEOUT


func _ready() -> void:
	var path := DEFAULT_SCRIPT
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--test-script="):
			path = arg.trim_prefix("--test-script=")
		elif arg.begins_with("--test-timeout="):
			_timeout = arg.trim_prefix("--test-timeout=").to_float()
	var script := load(path) as Script
	if script == null or not script.can_instantiate():
		print("  FAIL  test script '%s' could not be loaded (parse error?)" % path)
		print("HARNESS FAILED: test script did not load")
		get_tree().quit(EXIT_LOAD_FAILED)
		return
	get_tree().create_timer(_timeout, true, false, true).timeout.connect(_on_timeout)
	_test = Node.new()
	_test.name = "SmokeTest"
	_test.set_script(script)
	add_child(_test)


func _on_timeout() -> void:
	var section: Variant = _test.get("current_section") if is_instance_valid(_test) else null
	print("  FAIL  timed out after %.0fs (last section: %s)" % [_timeout, section if section else "?"])
	print("HARNESS FAILED: timeout")
	get_tree().quit(EXIT_TIMEOUT)
