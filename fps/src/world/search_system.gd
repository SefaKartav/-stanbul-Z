class_name SearchSystem
extends RefCounted
## TEK BIR mobilyayi (dolap, raf, cekmece, sandik) arama: sureli, gurultulu,
## kesilebilir. Bina cephesinden/ayak izinden toplu arama KALDIRILDI.
##
##   * ANINDA LOOT YOK: arama surer ve surerken gurultu yayar (risk karari).
##   * Oyuncu YERINDE DURMALI: kacarken yagmalamak yok.
##   * KESINTI POLITIKASI: hareket, hasar ya da E ile kesilirse ilerleme
##     container'da saklanir; geri gelince kaldigi yerden surer. Kesilen
##     aramada hic esya verilmez (eski "%50 ustu yarim odul" tasinmadi: ayni
##     binayi tekrar tekrar yarida keserek odul uretmek mumkundu).
##   * Arama bitince esya CANTAYA OTOMATIK DOLMAZ: loot paneli acilir, oyuncu
##     secer (bkz. LootScreen).

signal completed(plan: Dictionary, f: Dictionary, restock: bool)
signal interrupted(reason: String)
signal noise(position: Vector3, radius: float)

const CANCEL_MOVE := 1.25
const NOISE_INTERVAL := 1.2

var containers: ContainerRegistry
var skills := SkillProfile.new()
var session: Dictionary = {}


func _init(p_containers: ContainerRegistry) -> void:
	containers = p_containers


func active() -> bool:
	return not session.is_empty()


func progress() -> float:
	if session.is_empty():
		return -1.0
	return clampf(session.elapsed / maxf(0.01, session.duration), 0.0, 1.0)


func label() -> String:
	return str(session.get("label", ""))


func begin(plan: Dictionary, f: Dictionary, feet: Vector3, restock: bool = false) -> void:
	var def := ContainerRegistry.type_def(f.container)
	var duration := float(def.get("search_seconds", 2.5)) / maxf(0.2, skills.multiplier("search_speed"))
	session = {"plan": plan, "f": f, "origin": feet, "duration": duration,
		"elapsed": containers.progress(f.id) * duration, "noise_timer": 0.0, "restock": restock,
		"label": str(def.get("label", "Dolap")),
		"noise_radius": float(def.get("noise_m", 10.0)) * skills.multiplier("search_noise")}


func cancel(reason: String = "") -> void:
	if session.is_empty():
		return
	containers.set_progress(session.f.id, progress())
	session = {}
	interrupted.emit(reason)


func on_player_damaged() -> void:
	cancel("Hasar aldin -- arama kesildi (ilerleme saklandi)")


func update(delta: float, feet: Vector3) -> void:
	if session.is_empty():
		return
	var flat := Vector2(feet.x - session.origin.x, feet.z - session.origin.z)
	if flat.length() > CANCEL_MOVE:
		cancel("Yerinden oynadin -- arama kesildi (ilerleme saklandi)")
		return
	session.elapsed += delta
	session.noise_timer -= delta
	if session.noise_timer <= 0.0:
		session.noise_timer = NOISE_INTERVAL
		noise.emit(session.origin, session.noise_radius)
	if session.elapsed >= session.duration:
		var plan: Dictionary = session.plan
		var f: Dictionary = session.f
		var restock: bool = session.restock
		containers.set_progress(f.id, 0.0)
		session = {}
		completed.emit(plan, f, restock)
