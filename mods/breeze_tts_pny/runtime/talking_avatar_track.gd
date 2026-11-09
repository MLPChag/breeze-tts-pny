extends RefCounted
## Optional asynchronous analyzer. Failure disables mouth analysis, never speech.
const NATIVE := preload("res://mods/breeze_tts_pny/runtime/native_loader.gd")
const MODEL := "res://mods/breeze_tts_pny/native/viseme-model.bin"
const MODEL_SHA := "f1cdf2b76b9f2da8730b1d3e47d7e05a2b79c9b92d00dd00c595d64e471f419c"
static var _prepared := false
static var _ready_model := false
static var _model := PackedByteArray()
static var _warmup: RefCounted
var analyzer: RefCounted
var rate := 24000
var sent_bytes := 0
var eof_sent := false
var active := false
var cues: Array = []
var current := "X"
var utterance := ""
var _last_status: Dictionary = {}
var _reported_lag := false

static func enabled() -> bool:
	return NATIVE.supported()

static func prepare() -> bool:
	if _prepared: return _ready_model
	_prepared = true
	if not NATIVE.prepare(): return false
	if not ClassDB.class_exists("TalkingAvatarAnalyzer") or FileAccess.get_sha256(MODEL) != MODEL_SHA:
		push_warning("[talking-avatar] missing class or model hash mismatch")
		return false
	_model = FileAccess.get_file_as_bytes(MODEL)
	_ready_model = true
	# Parse/cache weights on a worker while the character is being prepared.
	_warmup = ClassDB.instantiate("TalkingAvatarAnalyzer")
	if _warmup.begin(_model, 24000): _warmup.finish()
	return true

func begin(id: String, sample_rate := 24000) -> bool:
	utterance = id; rate = sample_rate
	if not enabled() or not prepare(): return false
	analyzer = ClassDB.instantiate("TalkingAvatarAnalyzer")
	active = analyzer.begin(_model, rate)
	if active: print("[talking-avatar] begin ",utterance," rate=",rate)
	return active

func value_at(time: float, pcm: PackedByteArray, done: bool) -> String:
	if not active: return "X"
	_last_status = analyzer.status()
	if not str(_last_status.error).is_empty():
		push_warning("[talking-avatar] " + utterance + ": " + str(_last_status.error))
		cancel(); return "X"
	# Bound analysis to one second ahead of the audible clock, even for complete WAVs.
	var limit := mini(pcm.size(), int((maxf(0.0,time)+1.0)*rate)*2)
	limit -= limit % 2
	var count := 0
	while sent_bytes < limit and count < 4 and int(_last_status.pending_frames) < rate:
		var end := mini(limit, sent_bytes + int(rate * 0.08)*2)
		if not analyzer.push_pcm(pcm.slice(sent_bytes,end)):
			push_warning("[talking-avatar] input rejected: " + utterance)
			cancel(); return "X"
		sent_bytes = end; count += 1
	if done and sent_bytes == pcm.size() and not eof_sent:
		analyzer.finish(); eof_sent = true
	for cue: Dictionary in analyzer.poll():
		if done and float(cue.time) >= float(pcm.size())/(rate*2): continue
		cues.append(cue)
	if cues.size() > 256:
		push_warning("[talking-avatar] cue queue bound exceeded: " + utterance)
		cancel(); return "X"
	# Coalesce all expired changes in one update; never replay stale mouth motion.
	while not cues.is_empty() and float(cues[0].time) <= time:
		current = str(cues.pop_front().value)
	if not bool(_last_status.done) and float(_last_status.processed_frames)/rate + 0.2 < time:
		if not _reported_lag:
			print("[talking-avatar] lag ",utterance," at=",time)
			_reported_lag = true
		return "X"
	_reported_lag = false
	return current

func cancel() -> void:
	if analyzer != null:
		var stats: Dictionary = analyzer.status()
		analyzer.cancel()
		if active: print("[talking-avatar] end ",utterance," compute_ms=",stats.compute_ms," samples=",stats.total_frames)
	analyzer = null; active = false; cues.clear(); current = "X"
