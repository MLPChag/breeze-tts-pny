extends Node
const TRACK := preload("res://mods/breeze_tts_pny/runtime/talking_avatar_track.gd")
const INSTALL := preload("res://mods/breeze_tts_pny/runtime/install_extensions.gd")

func _enter_tree() -> void:
	if not TRACK.enabled(): return
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://mods/breeze_tts_pny/mod.json"))
	if not INSTALL.install(manifest.script_extensions):
		push_error("[breeze-tts-pny] Could not install speech extensions; remove this preview and restart.")

func _ready() -> void:
	var ready := TRACK.prepare() if TRACK.enabled() else false
	print("[breeze-tts-pny] 0.1.0 ", OS.get_name(), " preview; native lip-sync=", ready)
