extends SceneTree
var deadline := 0
var finished := false

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 180000
	start.call_deferred()

func _process(_delta: float) -> bool:
	if not finished and Time.get_ticks_msec() > deadline:
		printerr("WORLD_CYCLE_FAILED timeout"); quit(1)
	return false

func start() -> void:
	var saves: GDScript = load("res://world/game_saves.gd")
	saves.requested_world = "breeze_mod_fixture"
	saves.start_fresh = true
	change_scene_to_file("res://world/main.tscn")
	await await_game()

func await_game() -> void:
	while current_scene == null or current_scene.get("saves") == null:
		await process_frame
	var game: Node = current_scene
	var previous_id := game.get_instance_id()
	while not game.saves.ready_to_save:
		await process_frame
	printerr("WORLD_CYCLE_NEW_READY characters=", game.director.characters.size())
	if not game.director.tts.has_method("can_stream"):
		printerr("WORLD_CYCLE_FAILED unmodified TTS in real world"); quit(1); return
	root.get_node("TimeOfDay").day = 23
	if not game.saves.save_slot(0):
		printerr("WORLD_CYCLE_FAILED save rejected"); quit(1); return
	while game.saves.busy: await process_frame
	var path: String = game.saves.slot_path(0)
	# The test bypasses the title/save browser, so preserve its staged world id.
	load("res://world/game_saves.gd").requested_world = game.context_world_id
	root.get_node("TimeOfDay").day = 24
	if not FileAccess.file_exists(path) or not game.saves.load_save(path):
		printerr("WORLD_CYCLE_FAILED reload rejected"); quit(1); return
	await process_frame
	while current_scene == null or current_scene.get_instance_id() == previous_id or current_scene.get("saves") == null:
		await process_frame
	game = current_scene
	while not game.saves.ready_to_save: await process_frame
	if not game.director.tts.has_method("can_stream"):
		printerr("WORLD_CYCLE_FAILED TTS not extended after reload"); quit(1); return
	if root.get_node("TimeOfDay").day != 23 or game.context_world_id != "breeze_mod_fixture":
		printerr("WORLD_CYCLE_FAILED saved state was not restored"); quit(1); return
	printerr("WORLD_CYCLE_RELOADED_READY characters=", game.director.characters.size())
	finished = true
	printerr("BREEZE_WORLD_CYCLE_DONE")
	quit()
