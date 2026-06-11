extends Node
## Placeholder SFX (Plan.md sections 28 and 49): every sound is
## synthesized into a small PCM buffer at startup so the prototype has
## audio feedback before any real assets exist. Autoloaded as Sfx
## (after the gameplay managers, whose signals it listens to).

const MIX_RATE := 22050
const POOL_SIZE := 6

var _sounds: Dictionary = {}  # name -> {"stream": AudioStreamWAV, "db": float}
var _players: Array[AudioStreamPlayer] = []
# The headless dummy audio driver never mixes, so playbacks started
# there linger and get reported as leaked instances at exit.
var _enabled := DisplayServer.get_name() != "headless"

func _ready() -> void:
	_sounds = {
		"spray": {"stream": _spray_hiss(0.5), "db": -6.0},
		"denied": {"stream": _square_blip(110.0, 0.12), "db": -10.0},
		"ui": {"stream": _tone(880.0, 0.07), "db": -16.0},
		"rank_up": {"stream": _arpeggio([523.25, 659.25, 880.0], 0.11), "db": -8.0},
		"claim": {"stream": _arpeggio([392.0, 523.25, 659.25, 784.0], 0.13), "db": -6.0},
		"rival": {"stream": _rival_buzz(), "db": -9.0},
	}
	for i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_players.append(player)

	WallManager.wall_painted.connect(_on_wall_painted)
	GameState.rank_changed.connect(func(_rank: String) -> void: play("rank_up"))
	RivalManager.rival_event.connect(func(_msg: String, _wall: String) -> void: play("rival"))
	TerritoryManager.district_claimed.connect(func(_id: String, _d: Dictionary) -> void: play("claim"))
	CrewManager.crew_event.connect(func(_msg: String) -> void: play("ui"))
	SaveManager.save_event.connect(func(_msg: String) -> void: play("ui"))

## Active playbacks keep stream references alive inside the audio
## server; stop them so quitting doesn't report leaked instances.
func _exit_tree() -> void:
	for player in _players:
		player.stop()

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
