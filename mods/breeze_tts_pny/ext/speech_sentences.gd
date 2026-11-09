extends "res://world/ai/speech_sentences.gd"
## Group one speaker's short sentences into fuller synthesis requests.
## Keep the game's splitter, display paging and word timing through inheritance.
const AUDIO_TARGET := 160
const AUDIO_MAX := 400
const TINY_AUDIO := 48

static func audio_parts(text: String) -> Array[String]:
	var result: Array[String] = []
	var pending := ""
	for sentence: String in split(text):
		if not pending.is_empty() and pending.length() + sentence.length() + 1 > AUDIO_TARGET and pending.length() >= TINY_AUDIO:
			result.append(pending)
			pending = ""
		pending += (" " if not pending.is_empty() else "") + sentence
		while pending.length() > AUDIO_MAX:
			var end := pending.rfind(" ", AUDIO_MAX)
			if end <= 0: break # Preserve even an unusually long word intact.
			result.append(pending.left(end))
			pending = pending.substr(end + 1)
	if not pending.is_empty(): result.append(pending)
	return result

static func expand(beats: Array) -> Array:
	# The base's static expand calls its own audio_parts, so expansion must use
	# the grouped parts explicitly for both solo continuations and group lines.
	var result: Array = []
	for beat: Dictionary in beats:
		if bool(beat.get("silent_travel", false)):
			result.append(beat.duplicate(true))
			continue
		var emotion := ""
		var found := RegEx.create_from_string("^\\s*(\\[[a-zA-Z_ -]+\\])\\s*").search(beat.speech)
		if found: emotion = found.get_string(1) + " "
		var parts := audio_parts(beat.speech)
		var faces: Array = beat.get("face_map", [])
		var cursor := [0]
		var face := str(beat.get("face", ""))
		for index in parts.size():
			var part: String = parts[index]
			var clip := beat.duplicate(true)
			clip.speech = part
			clip.erase("face_map")
			if not faces.is_empty():
				face = preload("res://world/ai/pony_dialogue_tags.gd").face_for(faces, part, cursor, face)
				clip.face = face
			if index > 0:
				clip.actions = []
				clip.speech = emotion + part
			if index < parts.size() - 1: clip.erase("impression")
			clip["continuation"] = index > 0
			result.append(clip)
	return result
