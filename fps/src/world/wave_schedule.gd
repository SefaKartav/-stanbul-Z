class_name WaveSchedule
extends RefCounted
## Takvimli buyuk dalgalar (Python: world/siege.py).
##
## NORMAL GECELER SAKIN, HER N. GECE BUYUK DALGA. Takvim oyuncuya PLANLAMA
## UFKU verir ("iki gunum var, kuzey kapiyi guclendireyim"). Dalga onceden
## duyurulur; surpriz kusatma hazirligi odullendirmez, yalnizca cezalandirir.

const WAVE_INTERVAL_DAYS := 7
const WAVE_START := 0.83
const WAVE_END := 0.21
const BASE_WAVE_SIZE := 40
const WAVE_GROWTH := 22
const SIEGE_SPAWN_RADIUS_M := 56.0     # eski 900 px

var interval := WAVE_INTERVAL_DAYS
var first_wave_day := WAVE_INTERVAL_DAYS
var active_day := 0
var survived := 0


func next_wave_day(day: int, normalized: float) -> int:
	if day < first_wave_day:
		return first_wave_day
	var reference := day - 1 if normalized < WAVE_END else day
	if reference < first_wave_day:
		return first_wave_day
	var offset := (reference - first_wave_day) % interval
	if offset == 0 and normalized < WAVE_START:
		return reference
	return reference + (interval - offset)


func days_until(day: int, normalized: float) -> int:
	return maxi(0, next_wave_day(day, normalized) - day)


func is_wave_night(day: int, normalized: float) -> bool:
	if normalized >= WAVE_START:
		return _is_wave_day(day)
	if normalized < WAVE_END:
		return _is_wave_day(day - 1)
	return false


func _is_wave_day(day: int) -> bool:
	return day >= first_wave_day and (day - first_wave_day) % interval == 0


func wave_number(day: int) -> int:
	if day < first_wave_day:
		return 0
	return (day - first_wave_day) / interval + 1


func wave_size(day: int) -> int:
	return BASE_WAVE_SIZE + WAVE_GROWTH * (maxi(1, wave_number(day)) - 1)


func expected_size(day: int, normalized: float) -> int:
	return wave_size(next_wave_day(day, normalized))


func update(day: int, normalized: float) -> String:
	## 'started' / 'ended' / '' -- saf sinif; olay veriyoluna sahne baglar.
	## Ayni dalga iki kez baslamaz: `active_day` kayitta tutulur.
	var active_now := is_wave_night(day, normalized)
	var reference := day - 1 if normalized < WAVE_END else day
	if active_now and active_day != reference:
		active_day = reference
		return "started"
	if not active_now and active_day != 0:
		active_day = 0
		survived += 1
		return "ended"
	return ""


func active() -> bool:
	return active_day != 0


func to_dict() -> Dictionary:
	return {"interval": interval, "first_wave_day": first_wave_day,
		"active_day": active_day, "survived": survived}


func load_dict(data: Dictionary) -> void:
	interval = maxi(1, int(data.get("interval", WAVE_INTERVAL_DAYS)))
	first_wave_day = int(data.get("first_wave_day", WAVE_INTERVAL_DAYS))
	active_day = int(data.get("active_day", 0))
	survived = int(data.get("survived", 0))
