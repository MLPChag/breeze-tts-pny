extends RefCounted
## The 0.3.0 exported mod loader copies .gdc bases without their .gd remaps.
## Install the same subclasses from the entry node, with aliases confined to
## this mod's own cache. No game code is redistributed or patched on disk.
const CACHE := "user://mods/data/breeze_tts_pny/script-bases"
static var retained: Array[Script] = []

static func install(paths: Array) -> bool:
	if ProjectSettings.get_setting("application/config/version", "") != "0.3.0-maredev":
		push_warning("[breeze-tts-pny] This preview requires Home Equestria 0.3.0-maredev.")
		return false
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CACHE)) != OK: return false
	# A source replacement from the old development packs must not become our
	# parent: those packs already declare several of these members.
	if OS.has_feature("template"):
		for path: String in paths:
			var declaration := RegEx.create_from_string('(?m)^extends "(res://[^"\\n]+)"').search(FileAccess.get_file_as_string(path))
			if declaration == null: return false
			if FileAccess.file_exists(declaration.get_string(1)):
				push_warning("[breeze-tts-pny] A loose/replacement game script conflicts with this preview. Use an unmodified installed game directory.")
				return false
	var targets: Array[String] = []
	for path: String in paths:
		var text := FileAccess.get_file_as_string(path)
		var matched := RegEx.create_from_string('(?m)^extends "(res://[^"\\n]+)"').search(text)
		if matched == null: return false
		var target := matched.get_string(1)
		var base := load(target) as GDScript
		if base == null or not base.can_instantiate(): return false
		var stem := CACHE.path_join(str(targets.size()) + "_" + target.get_file().get_basename())
		var base_path := stem + ".gd"
		if not base.source_code.is_empty():
			DirAccess.remove_absolute(ProjectSettings.globalize_path(base_path + ".remap"))
			var source := RegEx.create_from_string("(?m)^class_name\\s+\\w+\\s*").sub(base.source_code, "", true)
			if not write(base_path, source.to_utf8_buffer()): return false
		else:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(base_path))
			if base.get_global_name() != &"": return false
			var bytes := FileAccess.get_file_as_bytes(target.get_basename() + ".gdc")
			if bytes.is_empty() or not write(stem + ".gdc", bytes): return false
			var remap := ConfigFile.new(); remap.set_value("remap", "path", stem + ".gdc")
			if remap.save(base_path + ".remap") != OK: return false
		var base_copy := load(base_path) as GDScript
		if base_copy == null or not base_copy.can_instantiate(): return false
		retained.append(base_copy)
		text = text.replace('extends "' + target + '"', 'extends "' + base_path + '"')
		var extension_path := stem + "_extension.gd"
		if not write(extension_path, text.to_utf8_buffer()): return false
		var extension := load(extension_path) as GDScript
		if extension == null or not extension.can_instantiate(): return false
		# Move the original off the public path too: later source preloads can
		# otherwise recover it from Godot's script cache instead of our subclass.
		base.take_over_path(stem + "_original.gd")
		extension.take_over_path(target)
		if extension.reload() != OK: return false
		retained.append(extension)
		targets.append(target)
		print("[breeze-tts-pny] extends ", target)
	return true

static func write(path: String, data: PackedByteArray) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return false
	file.store_buffer(data); file.close()
	return true
