extends "res://world/characters/openpony/openpony_mare.gd"
## Release-specific overlay: inherit shipped visuals, override speech only.
const PCM_UTTERANCE := preload("res://mods/breeze_tts_pny/runtime/pcm_utterance.gd")
const PCM_PLAYER := preload("res://mods/breeze_tts_pny/runtime/pcm_speech_player.gd")
const TA_TRACK := preload("res://mods/breeze_tts_pny/runtime/talking_avatar_track.gd")
const AUDIBLE_CLOCK := preload("res://mods/breeze_tts_pny/runtime/pcm_audible_clock.gd")
var _pcm_player: Node
var _ta_track: RefCounted
var _ta_clock: RefCounted
var _ta_wav: AudioStreamWAV
var _ta_clock_origin := 0

func _ready() -> void:
	super._ready()
	if TA_TRACK.enabled(): TA_TRACK.prepare()

func speak(wav_path: String, text := "") -> void:
	if not TA_TRACK.enabled():
		super.speak(wav_path,text)
		return
	stop_speaking()
	if wav_path.begins_with("pcm://"):
		_speak_pcm(wav_path)
		return
	var stream := LipSync.load_wav(wav_path)
	if stream == null or stream.get_length() <= 0.0:
		speech_failed.emit("Cannot load voice audio")
		return
	if stream.stereo or stream.format != AudioStreamWAV.FORMAT_16_BITS:
		super.speak(wav_path,text)
		return
	_pending_stream = stream
	_pending_path = wav_path
	_on_cues([])
	if TA_TRACK.enabled() and _speech_time >= 0.0 and voice.stream == stream and stream.format == AudioStreamWAV.FORMAT_16_BITS and not stream.stereo:
		_ta_wav = stream
		_ta_track = TA_TRACK.new()
		_ta_track.begin(wav_path,stream.mix_rate)

func stop_speaking() -> void:
	if _ta_track != null: _ta_track.cancel()
	_ta_track = null; _ta_clock = null; _ta_wav = null
	if is_instance_valid(_pcm_player):
		_pcm_player.cancel(); _pcm_player.queue_free(); _pcm_player = null
	super.stop_speaking()

func _unprofiled_process(delta: float) -> void:
	if is_instance_valid(_pcm_player):
		_speech_time = maxf(0.0,_pcm_player.consumed_frames/24000.0-AudioServer.get_output_latency())
		if _ta_track != null:
			_speech_time = _ta_clock.sample(float(Time.get_ticks_usec()-_ta_clock_origin)/1000000.0, _pcm_player.consumed_frames/24000.0, AudioServer.get_output_latency())
			var source: RefCounted = _pcm_player.source
			var letter: String = _ta_track.value_at(_speech_time,source.pcm,source.done)
			if mouth: mouth.set_viseme(letter)
		return
	if _ta_track != null and _ta_wav != null and _speech_time >= 0.0:
		var time := maxf(0.0,voice.get_playback_position()+AudioServer.get_time_since_last_mix()-AudioServer.get_output_latency())
		_cues = [{"start":0.0,"end":3600.0,"value":_ta_track.value_at(time,_ta_wav.data,true)}]
	super._unprofiled_process(delta)
	if _speech_time < 0.0 and _ta_track != null:
		_ta_track.cancel(); _ta_track = null; _ta_wav = null

func _speak_pcm(path: String) -> void:
	var utterance: RefCounted = PCM_UTTERANCE.take(path)
	if utterance == null or voice == null:
		if utterance != null: utterance.cancel()
		speech_failed.emit("PCM speech unavailable"); return
	_pending_path = path; _cues = []
	if mouth: mouth.set_viseme("X")
	_pcm_player = PCM_PLAYER.new(); add_child(_pcm_player)
	_pcm_player.started.connect(func():
		_speech_time = 0.0; set_process(true); speech_started.emit())
	_pcm_player.finished.connect(_pcm_finished)
	_pcm_player.failed.connect(_pcm_failed)
	_pcm_player.begin(utterance,voice)
	if TA_TRACK.enabled():
		_ta_track = TA_TRACK.new(); _ta_track.begin(utterance.uri)
		_ta_clock = AUDIBLE_CLOCK.new(); _ta_clock_origin = Time.get_ticks_usec()

func _pcm_finished() -> void:
	stop_speaking()
	speech_finished.emit()

func _pcm_failed(message: String) -> void:
	stop_speaking()
	speech_failed.emit(message)
