class_name Sfx
extends Node
## Ses efektleri: sabit kimlikler + yer tutucu sentez.
##
## Her ses bir KIMLIKLE calinir ("shot_pistol", "impact_glass"...).
## res://assets/audio/<kimlik>.ogg ya da .wav varsa o kullanilir; yoksa
## burada kisa bir sentez uretilir (gurultu patlamasi, darbe, tik).
## Final ses paketi geldiginde KOD DEGISMEZ; dosyalar klasore konur.
## Tam kimlik listesi: docs/VOXEL_FPS_ASSET_LISTESI.md

const AUDIO_DIR := "res://assets/audio/"
const RATE := 22050
const POOL_SIZE := 24

var _streams: Dictionary = {}
var _variants: Dictionary = {}     # kimlik -> [AudioStream] (<kimlik>_1, _2...)
var _pool: Array = []
var _pool_index := 0
var _ui_player: AudioStreamPlayer


func _ready() -> void:
	for i in POOL_SIZE:
		var player := AudioStreamPlayer3D.new()
		player.unit_size = 6.0
		player.max_distance = 140.0
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		player.bus = "Master"
		add_child(player)
		_pool.append(player)
	_ui_player = AudioStreamPlayer.new()
	add_child(_ui_player)


func stream(id: String) -> AudioStream:
	## Varyantli ses (<kimlik>_1, _2...): her cagrida rastgele biri -- ayni
	## silah/zombi art arda birebir ayni duyulmaz. Tek dosya ya da (hic dosya
	## yoksa) yer tutucu sentez.
	if not _variants.has(id):
		var list: Array = []
		var k := 1
		while true:
			var found := _load_file("%s_%d" % [id, k])
			if found == null:
				break
			list.append(found)
			k += 1
		_variants[id] = list
	var variants: Array = _variants[id]
	if not variants.is_empty():
		return variants[randi() % variants.size()]
	if _streams.has(id):
		return _streams[id]
	var result := _load_file(id)
	if result == null:
		result = _synthesize(id)
	_streams[id] = result
	return result


func _load_file(name: String) -> AudioStream:
	for ext: String in [".ogg", ".wav", ".mp3"]:
		if ResourceLoader.exists(AUDIO_DIR + name + ext):
			return load(AUDIO_DIR + name + ext)
	return null


func play_at(id: String, position: Vector3, volume_db: float = 0.0, pitch_jitter: float = 0.08) -> void:
	var player: AudioStreamPlayer3D = _pool[_pool_index]
	_pool_index = (_pool_index + 1) % POOL_SIZE
	player.stream = stream(id)
	# Silah sesi sokaklarda yuzlerce metre duyulur; adim/darbe yakin kalir.
	var loud := id.begins_with("shot_") or id in ["zombie_scream", "break_block"]
	player.max_distance = 450.0 if loud else 140.0
	player.unit_size = 14.0 if loud else 6.0
	player.global_position = position
	player.volume_db = volume_db
	player.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	player.play()


func play_ui(id: String, volume_db: float = -4.0) -> void:
	_ui_player.stream = stream(id)
	_ui_player.volume_db = volume_db
	_ui_player.play()


# ---------------------------------------------------------------------------
# Yer tutucu sentez
# ---------------------------------------------------------------------------
func _synthesize(id: String) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	var samples: PackedFloat32Array
	match id:
		"shot_pistol": samples = _gunshot(rng, 0.28, 0.35, 900.0, 1.0)
		"shot_revolver": samples = _gunshot(rng, 0.42, 0.5, 700.0, 1.0)
		"shot_shotgun": samples = _gunshot(rng, 0.55, 0.6, 400.0, 1.0)
		"shot_smg": samples = _gunshot(rng, 0.2, 0.3, 1200.0, 0.9)
		"shot_rifle": samples = _gunshot(rng, 0.6, 0.55, 600.0, 1.0)
		"shot_suppressed": samples = _gunshot(rng, 0.14, 0.12, 2400.0, 0.45)
		"melee_swing": samples = _whoosh(rng, 0.22)
		"melee_hit": samples = _thud(rng, 0.12, 140.0, 0.8)
		"dry_fire": samples = _click(rng, 0.03, 3200.0)
		"reload_out": samples = _click(rng, 0.06, 1800.0)
		"reload_in": samples = _double_click(rng)
		"equip": samples = _rattle(rng, 0.18)
		"impact_wood": samples = _thud(rng, 0.14, 260.0, 0.7)
		"impact_stone", "impact_concrete", "impact_brick": samples = _crack(rng, 0.12, 0.5)
		"impact_metal": samples = _ping(rng, 0.35, 1900.0)
		"impact_glass": samples = _shatter(rng, 0.25)
		"impact_dirt": samples = _thud(rng, 0.1, 120.0, 0.5)
		"impact_leaves": samples = _whoosh(rng, 0.12)
		"impact_water": samples = _whoosh(rng, 0.2)
		"impact_flesh": samples = _thud(rng, 0.1, 90.0, 0.9)
		"break_glass": samples = _shatter(rng, 0.6)
		"break_block": samples = _crumble(rng, 0.45)
		"footstep_hard": samples = _thud(rng, 0.07, 180.0, 0.35)
		"footstep_soft": samples = _thud(rng, 0.08, 90.0, 0.25)
		"zombie_groan": samples = _groan(rng, 1.1, 90.0)
		"zombie_alert": samples = _groan(rng, 0.7, 140.0)
		"zombie_attack": samples = _groan(rng, 0.35, 180.0)
		"zombie_death": samples = _groan(rng, 0.9, 70.0)
		"zombie_scream": samples = _groan(rng, 1.2, 260.0)
		"player_hurt": samples = _thud(rng, 0.2, 110.0, 1.0)
		"search_rustle": samples = _rustle(rng, 1.2)
		"pickup": samples = _blip(rng, 0.09, 880.0, 1320.0)
		"craft_done": samples = _blip(rng, 0.2, 660.0, 990.0)
		"ui_click": samples = _click(rng, 0.02, 2600.0)
		"ui_error": samples = _blip(rng, 0.18, 300.0, 220.0)
		"build_place": samples = _thud(rng, 0.18, 200.0, 0.9)
		"radio_static": samples = _rustle(rng, 0.8)
		_: samples = _click(rng, 0.05, 1000.0)
	return _to_wav(samples)


func _to_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav


func _buffer(seconds: float) -> PackedFloat32Array:
	var buffer := PackedFloat32Array()
	buffer.resize(int(seconds * RATE))
	return buffer


func _gunshot(rng: RandomNumberGenerator, seconds: float, body: float, crack_hz: float, gain: float) -> PackedFloat32Array:
	var out := _buffer(seconds)
	var lp := 0.0
	for i in out.size():
		var t := float(i) / RATE
		var noise := rng.randf_range(-1.0, 1.0)
		lp += (noise - lp) * clampf(crack_hz / RATE * 6.0, 0.01, 1.0)
		var crack := noise * exp(-t * 60.0)
		var boom := lp * exp(-t / maxf(0.02, body * 0.25)) * 1.8
		var thump := sin(TAU * 55.0 * t) * exp(-t * 18.0) * 0.8
		out[i] = (crack * 0.6 + boom + thump) * gain * 0.7
	return out


func _click(rng: RandomNumberGenerator, seconds: float, hz: float) -> PackedFloat32Array:
	var out := _buffer(seconds)
	for i in out.size():
		var t := float(i) / RATE
		out[i] = (sin(TAU * hz * t) * 0.5 + rng.randf_range(-0.5, 0.5)) * exp(-t * 120.0) * 0.6
	return out


func _double_click(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var a := _click(rng, 0.05, 2200.0)
	var out := _buffer(0.16)
	for i in a.size():
		out[i] += a[i]
		out[i + int(0.09 * RATE)] += a[i] * 1.2
	return out


func _rattle(rng: RandomNumberGenerator, seconds: float) -> PackedFloat32Array:
	var out := _buffer(seconds)
	for i in out.size():
		var t := float(i) / RATE
		var pulse := 1.0 if int(t * 40.0) % 3 == 0 else 0.3
		out[i] = rng.randf_range(-1, 1) * pulse * exp(-t * 14.0) * 0.35
	return out


func _thud(rng: RandomNumberGenerator, seconds: float, hz: float, gain: float) -> PackedFloat32Array:
	var out := _buffer(seconds)
	var lp := 0.0
	for i in out.size():
		var t := float(i) / RATE
		lp += (rng.randf_range(-1, 1) - lp) * 0.15
		out[i] = (sin(TAU * hz * t * (1.0 - t)) * 0.8 + lp * 0.8) * exp(-t * 30.0) * gain
	return out


func _crack(rng: RandomNumberGenerator, seconds: float, gain: float) -> PackedFloat32Array:
	var out := _buffer(seconds)
	for i in out.size():
		var t := float(i) / RATE
		out[i] = rng.randf_range(-1, 1) * exp(-t * 45.0) * gain + sin(TAU * 180.0 * t) * exp(-t * 35.0) * 0.3
	return out


func _ping(rng: RandomNumberGenerator, seconds: float, hz: float) -> PackedFloat32Array:
	var out := _buffer(seconds)
	for i in out.size():
		var t := float(i) / RATE
		out[i] = (sin(TAU * hz * t) + sin(TAU * hz * 1.51 * t) * 0.5) * exp(-t * 14.0) * 0.35 \
			+ rng.randf_range(-1, 1) * exp(-t * 90.0) * 0.4
	return out


func _shatter(rng: RandomNumberGenerator, seconds: float) -> PackedFloat32Array:
	var out := _buffer(seconds)
	var hp := 0.0
	var prev := 0.0
	for i in out.size():
		var t := float(i) / RATE
		var n := rng.randf_range(-1, 1)
		hp = n - prev
		prev = n
		var sparkle := sin(TAU * rng.randf_range(3000.0, 6000.0) * t) * (1.0 if rng.randf() < 0.02 else 0.0)
		out[i] = (hp * 0.6 + sparkle) * exp(-t * 7.0) * 0.6
	return out


func _crumble(rng: RandomNumberGenerator, seconds: float) -> PackedFloat32Array:
	var out := _buffer(seconds)
	var lp := 0.0
	for i in out.size():
		var t := float(i) / RATE
		lp += (rng.randf_range(-1, 1) - lp) * 0.08
		var grains := rng.randf_range(-1, 1) * (1.0 if rng.randf() < 0.05 else 0.1)
		out[i] = (lp * 1.4 + grains * 0.4) * exp(-t * 6.0) * 0.8
	return out


func _whoosh(rng: RandomNumberGenerator, seconds: float) -> PackedFloat32Array:
	var out := _buffer(seconds)
	var lp := 0.0
	for i in out.size():
		var t := float(i) / RATE
		lp += (rng.randf_range(-1, 1) - lp) * 0.2
		out[i] = lp * sin(PI * t / seconds) * 0.7
	return out


func _groan(rng: RandomNumberGenerator, seconds: float, hz: float) -> PackedFloat32Array:
	var out := _buffer(seconds)
	var phase := 0.0
	for i in out.size():
		var t := float(i) / RATE
		var wobble := hz * (1.0 + 0.15 * sin(TAU * 3.0 * t) + rng.randf_range(-0.02, 0.02))
		phase += TAU * wobble / RATE
		var voice := sin(phase) + 0.5 * sin(phase * 2.0) + 0.3 * sin(phase * 3.1)
		var envelope := sin(PI * clampf(t / seconds, 0.0, 1.0))
		out[i] = (voice * 0.3 + rng.randf_range(-0.15, 0.15)) * envelope * 0.6
	return out


func _rustle(rng: RandomNumberGenerator, seconds: float) -> PackedFloat32Array:
	var out := _buffer(seconds)
	for i in out.size():
		var t := float(i) / RATE
		var burst := 0.5 + 0.5 * sin(TAU * 7.0 * t + sin(t * 11.0))
		out[i] = rng.randf_range(-1, 1) * burst * 0.18
	return out


func _blip(_rng: RandomNumberGenerator, seconds: float, from_hz: float, to_hz: float) -> PackedFloat32Array:
	var out := _buffer(seconds)
	var phase := 0.0
	for i in out.size():
		var t := float(i) / RATE
		var hz := lerpf(from_hz, to_hz, t / seconds)
		phase += TAU * hz / RATE
		out[i] = sin(phase) * exp(-t * 10.0) * 0.35
	return out
