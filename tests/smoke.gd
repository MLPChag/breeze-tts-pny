extends SceneTree
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL ", message)
	else: printerr("PASS ", message)

func run() -> void:
	var disabled := "--disabled" in OS.get_cmdline_user_args()
	var mods := root.get_node("Mods")
	check(mods.is_active("breeze_tts_pny") == not disabled, "mod enabled state")
	var tts_script: GDScript = load("res://world/ai/tts_client.gd")
	var tts: Node = tts_script.new(); root.add_child(tts)
	check(tts.has_method("can_stream") == not disabled, "TTS subclass installed")
	var body: Node3D = load("res://world/characters/hybrid_mare/hybrid_mare.gd").new()
	check(body.has_method("supports_pcm_speech") == not disabled, "hybrid subclass installed")
	body.free()
	var spike: Node3D = load("res://world/characters/spike/spike.gd").new()
	check(spike.has_method("supports_pcm_speech") == not disabled, "Spike speech subclass installed")
	spike.free()
	var director: GDScript = load("res://world/ai/conversation_director.gd")
	check(director.can_instantiate(), "director compiles with extended TTS preload")
	var chunks: RefCounted = load(get_script().resource_path.get_base_dir().path_join("speech_chunks.gd")).new()
	failures += chunks.run(disabled)
	if not disabled:
		var base := director.get_base_script()
		var inner_tts: Node = base.get_script_constant_map().TTS.new()
		check(inner_tts.has_method("can_stream"), "director's captured TTS class is extended")
		inner_tts.free()
	var later := GDScript.new()
	later.source_code = 'extends RefCounted\nconst TTS := preload("res://world/ai/tts_client.gd")\nconst HEAD := preload("res://world/characters/openpony/openpony_mare.gd")\n'
	check(later.reload() == OK, "later preloads retain extended classes")
	var later_tts: Node = later.get_script_constant_map().TTS.new()
	check(later_tts.has_method("can_stream") == not disabled, "later TTS preload uses the selected speech implementation")
	later_tts.free()
	var head: Node3D = load("res://world/characters/openpony/openpony_mare.gd").new()
	root.add_child(head)
	check(head.has_method("_speak_pcm") == not disabled, "OpenPony speech subclass installed")
	for mesh in head.model.find_children("*", "MeshInstance3D", true, false):
		if mesh.name != "Eye" and not str(mesh.name).begins_with("Pupil"): continue
		printerr("EYE_MESH ", mesh.name, " visible=", mesh.visible)
		for i in mesh.mesh.get_surface_count():
			var material: Material = mesh.get_active_material(i)
			if material is ShaderMaterial:
				printerr("EYE_SHADER ", material.shader.resource_path)
				for param in material.shader.get_shader_uniform_list():
					var value: Variant = material.get_shader_parameter(param.name)
					printerr("UNIFORM ", param.name, "=", value.resource_path if value is Resource else value)
	if not disabled:
		var track_script: GDScript = load("res://mods/breeze_tts_pny/runtime/talking_avatar_track.gd")
		check(track_script.prepare(), "embedded native library extracted and loaded")
		check(ClassDB.class_exists("TalkingAvatarAnalyzer"), "native analyzer available")
		var analyzer: RefCounted = ClassDB.instantiate("TalkingAvatarAnalyzer")
		var model := FileAccess.get_file_as_bytes("res://mods/breeze_tts_pny/native/viseme-model.bin")
		check(analyzer.begin(model, 24000), "worker begins")
		var pcm := PackedByteArray(); pcm.resize(48000)
		for i in 24000: pcm.encode_s16(i * 2, int(sin(float(i) * TAU * 220.0 / 24000.0) * 12000.0))
		check(analyzer.push_pcm(pcm), "worker accepts bounded PCM")
		analyzer.finish()
		var deadline := Time.get_ticks_msec() + 5000
		while not analyzer.status().done and Time.get_ticks_msec() < deadline:
			await create_timer(.01).timeout
		check(analyzer.status().done and str(analyzer.status().error).is_empty(), "worker finishes without model error")
		check(not analyzer.poll().is_empty(), "native cue output")
		analyzer.cancel()
		var list: Array = mods.list()
		for item: Dictionary in list:
			if item.id == "breeze_tts_pny":
				check(not mods.switch(item.file, false), "disabling this mod correctly requires restart")
	head.queue_free(); tts.queue_free()
	await process_frame
	printerr("BREEZE_MOD_SMOKE_DONE failures=", failures)
	quit(0 if failures == 0 else 1)
