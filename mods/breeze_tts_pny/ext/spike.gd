extends "res://world/characters/spike/spike.gd"
## Keep Spike's shipped body/face animation; replace only speech playback.
const PCM_UTTERANCE := preload("res://mods/breeze_tts_pny/runtime/pcm_utterance.gd")
const PCM_PLAYER := preload("res://mods/breeze_tts_pny/runtime/pcm_speech_player.gd")
const TA_TRACK := preload("res://mods/breeze_tts_pny/runtime/talking_avatar_track.gd")
const AUDIBLE_CLOCK := preload("res://mods/breeze_tts_pny/runtime/pcm_audible_clock.gd")
var _pcm_player: Node
var _ta_track: RefCounted
var _ta_clock: RefCounted
var _ta_wav: AudioStreamWAV
var _ta_clock_origin := 0
var _breeze_speech := false

func supports_pcm_speech() -> bool:
	return TA_TRACK.enabled() and is_instance_valid(_voice)

func say(wav_path: String, text := "") -> void:
	if not TA_TRACK.enabled():
		super.say(wav_path, text)
		return
	stop_speaking()
	if wav_path.begins_with("pcm://"):
		_speak_pcm(wav_path)
		return
	var stream := LipSync.load_wav(wav_path)
	if stream == null or stream.get_length() <= 0.0:
		speech_failed.emit("Cannot load voice audio")
		return
	if stream.stereo or stream.format != AudioStreamWAV.FORMAT_16_BITS or stream.mix_rate not in [24000, 48000]:
		super.say(wav_path, text)
		return
	_breeze_speech = true
	_pending_path = wav_path
	_pending_stream = stream
	_ta_wav = stream
	_ta_track = TA_TRACK.new()
	_ta_track.begin(wav_path, stream.mix_rate)
	# Start now; the analyzer supplies current/future cues on its worker.
	super._on_cues([], _speech_generation)

func stop_speaking() -> void:
	if _breeze_speech:
		_breeze_speech = false
		if _ta_track != null: _ta_track.cancel()
		_ta_track = null; _ta_clock = null; _ta_wav = null
		if is_instance_valid(_pcm_player):
			_pcm_player.cancel(); _pcm_player.queue_free(); _pcm_player = null
		# The stock stop method emits completion for an interrupted line. Clear
		# our speaking state first: only a drained, valid stream is completion.
		_speech_time = -1.0
		_cues = []
		if expressions != null: expressions.viseme = "X"
	super.stop_speaking()

func _process(delta: float) -> void:
	var audible := -1.0
	if _breeze_speech and _speech_time >= 0.0:
		var letter := "X"
		if is_instance_valid(_pcm_player):
			audible = _ta_clock.sample(float(Time.get_ticks_usec() - _ta_clock_origin) / 1000000.0,
				_pcm_player.consumed_frames / 24000.0, AudioServer.get_output_latency())
			var source: RefCounted = _pcm_player.source
			letter = _ta_track.value_at(audible, source.pcm, source.done)
		elif _ta_wav != null:
			audible = maxf(0.0, _voice.get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency())
			letter = _ta_track.value_at(audible, _ta_wav.data, true)
		_speech_time = audible
		_cues = [{"start":0.0, "end":3600.0, "value":letter}]
	# The base applies our cue to Spike's blend shapes alongside gestures,
	# blinking, expressions and gaze. Undo only its wall-clock speech increment.
	super._process(delta)
	if _breeze_speech and audible >= 0.0: _speech_time = audible

func speech_progress() -> Dictionary:
	if _breeze_speech and is_instance_valid(_pcm_player):
		return {"time":maxf(0.0, _speech_time), "duration":0.0}
	return super.speech_progress()

func _speak_pcm(path: String) -> void:
	var utterance: RefCounted = PCM_UTTERANCE.take(path)
	if utterance == null or not is_instance_valid(_voice):
		if utterance != null: utterance.cancel()
		speech_failed.emit("PCM speech unavailable")
		return
	_breeze_speech = true
	_pending_path = path
	_cues = []
	expressions.viseme = "X"
	_ta_track = TA_TRACK.new(); _ta_track.begin(utterance.uri)
	_ta_clock = AUDIBLE_CLOCK.new(); _ta_clock_origin = Time.get_ticks_usec()
	_pcm_player = PCM_PLAYER.new(); add_child(_pcm_player)
	_pcm_player.started.connect(func():
		_speech_time = 0.0; speech_started.emit())
	_pcm_player.finished.connect(_pcm_finished)
	_pcm_player.failed.connect(_pcm_failed)
	_pcm_player.begin(utterance, _voice)

func _on_voice_finished() -> void:
	if _breeze_speech:
		# A generator's lifetime is owned by PCM_PLAYER, including final drain.
		if not is_instance_valid(_pcm_player): _pcm_finished()
		return
	super._on_voice_finished()

func _pcm_finished() -> void:
	if not _breeze_speech: return
	stop_speaking()
	speech_finished.emit()

func _pcm_failed(message: String) -> void:
	if not _breeze_speech: return
	stop_speaking()
	speech_failed.emit(message)

func _exit_tree() -> void:
	if _breeze_speech: stop_speaking()
