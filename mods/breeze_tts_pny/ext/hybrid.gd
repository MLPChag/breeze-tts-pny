extends "res://world/characters/hybrid_mare/hybrid_mare.gd"
## Preserve the shipped hybrid appearance, gaze and animation implementation.
func supports_pcm_speech() -> bool:
	return is_instance_valid(head) and head.has_method("_speak_pcm")

func speech_progress() -> Dictionary:
	if is_instance_valid(head) and is_instance_valid(head.get("_pcm_player")):
		return {"time":maxf(0.0,head._speech_time),"duration":0.0}
	return super.speech_progress()
