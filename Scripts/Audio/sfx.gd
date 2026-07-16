extends Node
## Placeholder SFX (GDD sections 28 and 49): every sound is
## synthesized into a small PCM buffer at startup so the prototype has
## audio feedback before any real assets exist. Autoloaded as Sfx
## (after the gameplay managers, whose signals it listens to).

const MIX_RATE := 22050
const POOL_SIZE := 6

var _sounds: Dictionary = {}  # name -> {"stream": AudioStreamWAV, "db": float}
var _players: Array[AudioStreamPlayer] = []
var _music_player: AudioStreamPlayer
var _ambience_player: AudioStreamPlayer
# The headless dummy audio driver never mixes, so playbacks started
# there linger and get reported as leaked instances at exit.
var _enabled := DisplayServer.get_name() != "headless"
var _continuous_started := false
var _rank_index := 0

func _ready() -> void:
	_sounds = {
		"spray": {"stream": _spray_hiss(0.5), "db": -6.0},
		"denied": {"stream": _square_blip(110.0, 0.12), "db": -10.0},
		"ui": {"stream": _tone(880.0, 0.07), "db": -16.0},
		"rank_up": {"stream": _arpeggio([523.25, 659.25, 880.0], 0.11), "db": -8.0},
		"claim": {"stream": _arpeggio([392.0, 523.25, 659.25, 784.0], 0.13), "db": -6.0},
		"rival": {"stream": _rival_buzz(), "db": -9.0},
		"buff": {"stream": _roller_swipe(), "db": -10.0},
		"whistle": {"stream": _arpeggio([1567.98, 1244.51, 1567.98], 0.09), "db": -9.0},
		"rest": {"stream": _arpeggio([329.63, 392.0, 493.88], 0.16), "db": -12.0},
	}
	for i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_players.append(player)
	if _enabled:
		_music_player = AudioStreamPlayer.new()
		_music_player.volume_db = -24.0
		add_child(_music_player)
		_ambience_player = AudioStreamPlayer.new()
		_ambience_player.volume_db = -28.0
		add_child(_ambience_player)

	WallManager.wall_painted.connect(_on_wall_painted)
	_rank_index = GameState.rank_index(GameState.rank)
	GameState.rank_changed.connect(_on_rank_changed)
	GameState.alias_changed.connect(func(_alias: String) -> void:
		_start_continuous_audio())
	PatrolManager.player_spotted.connect(func(_g: PatrolGuard) -> void: play("whistle"))
	PatrolManager.player_caught.connect(func(_g: PatrolGuard) -> void: play("denied"))
	RivalManager.rival_event.connect(func(_msg: String, _wall: String) -> void: play("rival"))
	HeatManager.cleanup_event.connect(func(_msg: String, _wall: String) -> void: play("buff"))
	GameState.district_changed.connect(_set_ambience)
	GameState.safehouse_rest_changed.connect(func(_rests: int) -> void: play("rest"))
	TerritoryManager.district_claimed.connect(func(_id: String, _d: Dictionary) -> void: play("claim"))
	CrewManager.crew_event.connect(func(_msg: String) -> void: play("ui"))
	SupplyManager.supply_event.connect(func(_msg: String) -> void: play("ui"))
	DialogueManager.dialogue_event.connect(func(_msg: String) -> void: play("ui"))
	SaveManager.save_event.connect(func(_msg: String) -> void: play("ui"))
	TrainManager.train_painted.connect(func(_id: String, _g: Dictionary) -> void: play("spray"))
	TrainManager.train_passed.connect(func(_id: String, _d: String, _rep: int) -> void: play("ui"))
	GalleryManager.gallery_event.connect(func(_msg: String) -> void: play("ui"))
	GalleryManager.commission_resolved.connect(func(result: Dictionary) -> void:
		if result.get("accepted", false):
			play("claim"))

## Active playbacks keep stream references alive inside the audio
## server; stop them so quitting doesn't report leaked instances.
func _exit_tree() -> void:
	for player in _players:
		player.stop()
		player.stream = null
	if _music_player != null:
		_music_player.stop()
		_music_player.stream = null
	if _ambience_player != null:
		_ambience_player.stop()
		_ambience_player.stream = null

func play(sound_name: String) -> void:
	if not _enabled:
		return
	var sound: Dictionary = _sounds.get(sound_name, {})
	if sound.is_empty():
		return
	for player in _players:
		if not player.playing:
			player.stream = sound["stream"]
			player.volume_db = float(sound["db"])
			player.play()
			return

func _set_ambience(district_id: String) -> void:
	if not _enabled or not _continuous_started or _ambience_player == null:
		return
	_ambience_player.stop()
	var base := 72.0 if district_id == "district_canal_side" else 58.0
	_ambience_player.stream = _loop(_ambience_bed(base))
	_ambience_player.play()

func _start_continuous_audio() -> void:
	if not _enabled or _continuous_started or _music_player == null:
		return
	_continuous_started = true
	_music_player.stream = _loop(_music_bed())
	_music_player.play()
	_set_ambience(GameState.current_district_id)

## Rising sting only for actual rank-ups — a patrol catch can demote.
func _on_rank_changed(rank: String) -> void:
	var idx := GameState.rank_index(rank)
	play("rank_up" if idx > _rank_index else "denied")
	_rank_index = idx

func _on_wall_painted(_wall_id: String, graffiti: Dictionary) -> void:
	# Rival repaints happen off-screen on the simulation tick; the
	# rival_event buzz already covers those.
	if String(graffiti.get("creatorId", "")) == "player":
		play("spray")

## Spray-can hiss: smoothed white noise with a fast attack and long decay.
func _spray_hiss(length: float) -> AudioStreamWAV:
	var count := int(length * MIX_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	var filtered := 0.0
	for i in count:
		var t := float(i) / count
		var envelope := minf(t / 0.04, 1.0) * pow(1.0 - t, 0.6)
		filtered = filtered * 0.7 + rng.randf_range(-1.0, 1.0) * 0.3
		samples[i] = filtered * envelope
	return _to_wav(samples)

func _tone(freq: float, length: float) -> AudioStreamWAV:
	var count := int(length * MIX_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in count:
		var t := float(i) / count
		samples[i] = sin(TAU * freq * i / MIX_RATE) * (1.0 - t) * 0.8
	return _to_wav(samples)

func _square_blip(freq: float, length: float) -> AudioStreamWAV:
	var count := int(length * MIX_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in count:
		var t := float(i) / count
		var square := 1.0 if fmod(freq * i / MIX_RATE, 1.0) < 0.5 else -1.0
		samples[i] = square * (1.0 - t) * 0.5
	return _to_wav(samples)

## Sequential rising notes — used for rank-ups and the block-claim payoff.
func _arpeggio(freqs: Array, note_length: float) -> AudioStreamWAV:
	var note_count := int(note_length * MIX_RATE)
	var samples := PackedFloat32Array()
	samples.resize(note_count * freqs.size())
	for n in freqs.size():
		var freq := float(freqs[n])
		for i in note_count:
			var t := float(i) / note_count
			samples[n * note_count + i] = sin(TAU * freq * i / MIX_RATE) * (1.0 - t) * 0.7
	return _to_wav(samples)

## Dull paint-roller swipe (heavily smoothed noise with a slow hump
## envelope) — city cleanup just buffed a wall.
func _roller_swipe() -> AudioStreamWAV:
	var length := 0.5
	var count := int(length * MIX_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var filtered := 0.0
	for i in count:
		var t := float(i) / count
		filtered = filtered * 0.93 + rng.randf_range(-1.0, 1.0) * 0.07
		samples[i] = filtered * sin(PI * t) * 2.2
	return _to_wav(samples)

## Descending square-wave buzz — a rival just disrespected you.
func _rival_buzz() -> AudioStreamWAV:
	var length := 0.35
	var count := int(length * MIX_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var phase := 0.0
	for i in count:
		var t := float(i) / count
		phase += lerpf(200.0, 140.0, t) / MIX_RATE
		var square := 1.0 if fmod(phase, 1.0) < 0.5 else -1.0
		samples[i] = square * (1.0 - t) * 0.45
	return _to_wav(samples)

func _music_bed() -> AudioStreamWAV:
	var count := int(8.0 * MIX_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var notes: Array[float] = [55.0, 65.41, 73.42, 82.41]
	for i in count:
		var beat := int(float(i) / MIX_RATE * 2.0) % notes.size()
		var freq: float = notes[beat]
		var t := float(i) / MIX_RATE
		samples[i] = (sin(TAU * freq * t) * 0.25
			+ sin(TAU * freq * 2.0 * t) * 0.08) * 0.55
	return _to_wav(samples)

func _ambience_bed(base_freq: float) -> AudioStreamWAV:
	var count := int(6.0 * MIX_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(base_freq * 100.0)
	var filtered := 0.0
	for i in count:
		var t := float(i) / MIX_RATE
		filtered = filtered * 0.985 + rng.randf_range(-1.0, 1.0) * 0.015
		samples[i] = filtered * 0.45 + sin(TAU * base_freq * 0.25 * t) * 0.08
	return _to_wav(samples)

func _loop(stream: AudioStreamWAV) -> AudioStreamWAV:
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = stream.data.size() / 2
	return stream

func _to_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = bytes
	return wav
