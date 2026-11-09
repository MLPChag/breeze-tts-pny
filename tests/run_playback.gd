extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var script: GDScript = load(OS.get_cmdline_user_args()[1])
	if script == null or not script.can_instantiate(): quit(1); return
	root.add_child(script.new())
