extends "res://world/ai/conversation_director.gd"
## Exercise the real speech request/handoff without starting LLM/STT services.
var received_live := false

func _ready() -> void:
	set_process(false)
	_tag_regex.compile(EMOTION_TAG)

func _exit_tree() -> void: pass
func _listener_available() -> bool: return true

func _on_tts(path: String, error: String, turn_id := -1, voice_id := -1) -> void:
	received_live = path.begins_with("pcm://") and tts.busy
	super._on_tts(path, error, turn_id, voice_id)
