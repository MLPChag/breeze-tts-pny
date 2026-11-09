extends "res://world/ai/conversation_director.gd"

func _voice_error(why: String) -> void:
	if why.begins_with("PCM ") and _recorded:
		_fail(why)
		return
	super._voice_error(why)

func _prefetch_next() -> void:
	if tts.has_method("can_stream") and tts.can_stream() and tts.busy: return
	super._prefetch_next()

func _synthesize_voice(text: String, profile: Dictionary, emotion: String, callback: Callable) -> bool:
	var actor: Node = characters.get(str(profile.get("id", "")), {}).get("node")
	if tts.has_method("can_stream") and tts.can_stream() and callback.get_method() == "_on_tts" and is_instance_valid(actor) and actor.has_method("supports_pcm_speech") and actor.supports_pcm_speech():
		text = clean_reply(text)
		if _strip_tag(text).is_empty():
			callback.call_deferred("", "no generated speech to synthesize")
			return true
		if not tts.live_render_finished.is_connected(_on_live_render_finished):
			tts.live_render_finished.connect(_on_live_render_finished)
		return tts.synthesize_profile_live(text, profile, emotion, callback)
	return super._synthesize_voice(text, profile, emotion, callback)

func _on_live_render_finished() -> void:
	if state == "speaking" and group.active() and _prefetch_index != group.cursor:
		_prefetch_next()
