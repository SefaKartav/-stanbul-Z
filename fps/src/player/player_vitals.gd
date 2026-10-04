class_name PlayerVitals
extends RefCounted
## Oyuncunun cani, enerjisi (yetenekler icin), KISISEL toklugu ve
## hidrasyonu, durum etkileri.
##
## ACLIK VE SUSUZLUK (25 Eylul 2026)
##   * Tokluk ve hidrasyon 0-100, koloninin ortak stokundan AYRIDIR: ussun
##     deposu oyuncuyu uzaktan beslemez. Oyuncu envanterinden yer/icer.
##   * Hiz OYUN SAATINE baglidir (kare sayisina degil): Game her adimda
##     gecen oyun saatini verir; duraklatilmis menude dunya durur, ihtiyac da.
##     Etkinlik carpani: depar/kosu/asiri yuk.
##   * Esikler asamalidir: dusuk -> nefes tavani ve yenilenmesi duser; kritik
##   -> daha cok; sifirda UYARILMIS bir bekleme suresinden (yemek 8, su 3 oyun
##     saati) sonra can kaybi baslar. Susuzluk daha aciliyetlidir. Oyuncu
##     hareketsiz kalmaz: nefes tavani en az %35.
##   * Degerler data/world/nutrition.json'dadir (zorluk carpanlari dahil).

signal damaged(amount: float, direction: Vector3)
signal died
signal need_warning(text: String, urgent: bool)

const MAX_HEALTH := 100.0
const BASE_ENERGY := 100.0
const BASE_ENERGY_REGEN := 7.5
const INVULN_TIME := 0.25          # ust uste binen zombi vuruslarini seyreltir
const SICK := "sick"

var health := MAX_HEALTH
var energy := BASE_ENERGY
var energy_max := BASE_ENERGY
var energy_regen := BASE_ENERGY_REGEN
var armor := 0.0
var toxin_resist := 0.0            # gaz maskesi: asit/zehir hasari x (1 - direnç)
var statuses := StatusEffects.new()
var dead := false
var starving := false              # tokluk kritik (eski alan: yetenek enerjisini kisar)
var satiety := 80.0
var hydration := 80.0
var food_zero_hours := 0.0         # tokluk sifirda gecen oyun saati
var water_zero_hours := 0.0
var _warned := {}                  # esik -> true (ayni uyari tekrar tekrar gelmesin)
var _invuln := 0.0
var stabilize := false             # beceri: Saha stabilizasyonu
var _stab_left := 0.0              # etkin pencere (sn)
var _stab_cooldown := 0.0


func ratio() -> float:
	return health / MAX_HEALTH


static func config() -> Dictionary:
	return Content.nutrition


func tick(delta: float, skills: SkillProfile) -> void:
	if dead:
		return
	_invuln = maxf(0.0, _invuln - delta)
	_stab_left = maxf(0.0, _stab_left - delta)
	_stab_cooldown = maxf(0.0, _stab_cooldown - delta)
	starving = satiety <= float(config().get("effects", {}).get("critical", 10))
	energy_max = BASE_ENERGY * (0.55 if starving else 1.0)
	energy_regen = BASE_ENERGY_REGEN * (0.5 if starving else 1.0) * regen_factor()
	energy = minf(energy_max, energy + energy_regen * delta)
	var dot := statuses.tick(delta, skills.bonus("status_resistance"))
	if dot > 0.0:
		_lose(dot)
	var regen := statuses.regen_rate()
	if regen > 0.0 and not dead:
		health = minf(MAX_HEALTH, health + regen * delta)


func tick_needs(game_hours: float, activity: String, skills: SkillProfile = null) -> void:
	## Gecen OYUN SAATI kadar tokluk/hidrasyon harcar. Kare hizindan bagimsiz:
	## 30/60/144 FPS ayni oyun saatinde ayni sonucu verir (test_survival).
	if dead or game_hours <= 0.0:
		return
	var cfg := config()
	var rates: Dictionary = cfg.get("rates", {})
	var diff := float(rates.get("difficulty", {}).get(Settings.difficulty, 1.0))
	var act := float(rates.get("activity", {}).get(activity, 1.0))
	var food_rate := float(rates.get("satiety_per_hour", 1.1)) * diff * act
	var water_rate := float(rates.get("hydration_per_hour", 1.85)) * diff * act
	if skills != null:
		food_rate *= skills.multiplier("food_need")
		water_rate *= skills.multiplier("water_need")
	var effects: Dictionary = cfg.get("effects", {})
	if statuses.has(SICK):
		water_rate += float(effects.get("sick_hydration_per_hour", 2.0))
	satiety = clampf(satiety - food_rate * game_hours, 0.0, 100.0)
	hydration = clampf(hydration - water_rate * game_hours, 0.0, 100.0)
	var grace: Dictionary = effects.get("grace_hours", {})
	var per_hour: Dictionary = effects.get("damage_per_hour", {})
	var dmg_diff := float(effects.get("damage_difficulty", {}).get(Settings.difficulty, 1.0))
	food_zero_hours = food_zero_hours + game_hours if satiety <= 0.0 else 0.0
	water_zero_hours = water_zero_hours + game_hours if hydration <= 0.0 else 0.0
	var loss := 0.0
	if food_zero_hours > float(grace.get("food", 8.0)):
		loss += float(per_hour.get("food", 2.0)) * dmg_diff * game_hours
	if water_zero_hours > float(grace.get("water", 3.0)):
		loss += float(per_hour.get("water", 4.5)) * dmg_diff * game_hours
	if loss > 0.0:
		_lose(loss)
	_warnings()


func _warnings() -> void:
	var effects: Dictionary = config().get("effects", {})
	var low := float(effects.get("low", 25))
	var critical := float(effects.get("critical", 10))
	for entry: Array in [["water", hydration, "Susadin -- nefesin cabuk tukenecek", "SUSUZLUK kritik: su bul ya da ic (U)",
			"Susuzluk canini yiyor! Hemen su ic."],
			["food", satiety, "Acsin -- dayanikliligin dusuyor", "ACLIK kritik: bir seyler ye (N)",
			"Aclik canini yiyor! Hemen ye."]]:
		var kind: String = entry[0]
		var value: float = entry[1]
		if value > low + 5.0:
			for level: String in ["low", "critical", "zero"]:
				_warned.erase(kind + level)
			continue
		if value <= low and not _warned.has(kind + "low"):
			_warned[kind + "low"] = true
			need_warning.emit(entry[2], false)
		if value <= critical and not _warned.has(kind + "critical"):
			_warned[kind + "critical"] = true
			need_warning.emit(entry[3], true)
		if value <= 0.0 and not _warned.has(kind + "zero"):
			_warned[kind + "zero"] = true
			var grace: float = float(effects.get("grace_hours", {}).get(kind, 3.0))
			need_warning.emit("%s (%.0f oyun saati icinde can kaybi baslar)" % [entry[4], grace], true)


func _level(value: float) -> String:
	var effects: Dictionary = config().get("effects", {})
	if value <= 0.0:
		return "empty"
	if value <= float(effects.get("critical", 10)):
		return "critical"
	if value <= float(effects.get("low", 25)):
		return "low"
	return "ok"


func stamina_cap() -> float:
	## Nefes tavani: tokluk ve hidrasyonun kotusu belirler (en az %35).
	var caps: Dictionary = config().get("effects", {}).get("stamina_cap", {})
	var worst := 100.0
	for value: float in [satiety, hydration]:
		var level := _level(value)
		if level != "ok":
			worst = minf(worst, float(caps.get(level, 100)))
	if statuses.has(SICK):
		worst = minf(worst, 70.0)
	return maxf(35.0, worst)


func regen_factor() -> float:
	var factors: Dictionary = config().get("effects", {}).get("regen_factor", {})
	var worst := 1.0
	for value: float in [satiety, hydration]:
		var level := _level(value)
		if level != "ok":
			worst = minf(worst, float(factors.get(level, 1.0)))
	return worst


func hours_until(kind: String, activity: String = "walk") -> float:
	## Bu degerin dusuk esige inmesine kalan OYUN saati (tahmin).
	var rates: Dictionary = config().get("rates", {})
	var diff := float(rates.get("difficulty", {}).get(Settings.difficulty, 1.0))
	var act := float(rates.get("activity", {}).get(activity, 1.0))
	var low := float(config().get("effects", {}).get("low", 25))
	var value := satiety if kind == "food" else hydration
	var rate := float(rates.get("satiety_per_hour" if kind == "food" else "hydration_per_hour", 1.0)) * diff * act
	return maxf(0.0, (value - low) / maxf(0.01, rate))


func feed(food: float, water: float) -> void:
	satiety = clampf(satiety + food, 0.0, 100.0)
	hydration = clampf(hydration + water, 0.0, 100.0)
	if satiety > 0.0:
		food_zero_hours = 0.0
	if hydration > 0.0:
		water_zero_hours = 0.0


func take_hit(amount: float, damage_type: String, direction: Vector3) -> float:
	## Zombi vurusu gibi dis hasar. Uygulanan hasari dondurur.
	if dead or _invuln > 0.0:
		return 0.0
	var dealt := amount * statuses.damage_taken_multiplier()
	if damage_type in ["acid", "toxin"]:
		dealt *= 1.0 - clampf(toxin_resist, 0.0, 0.9)
	if damage_type != "true":
		dealt = maxf(dealt * 0.1, dealt - armor)
	# Saha stabilizasyonu: can %20'nin altina inerken 10 sn %30 az hasar (90 sn'de bir).
	if stabilize and _stab_left <= 0.0 and _stab_cooldown <= 0.0 and health - dealt < MAX_HEALTH * 0.2:
		_stab_left = 10.0
		_stab_cooldown = 90.0
		need_warning.emit("Saha stabilizasyonu: 10 sn boyunca daha az hasar", false)
	if _stab_left > 0.0:
		dealt *= 0.7
	_invuln = INVULN_TIME
	_lose(dealt)
	damaged.emit(dealt, direction)
	return dealt


func heal(amount: float, cures: Array = []) -> void:
	if dead:
		return
	health = minf(MAX_HEALTH, health + amount)
	for kind: String in cures:
		statuses.remove(kind)


func spend_energy(amount: float) -> bool:
	if energy < amount:
		return false
	energy -= amount
	return true


func _lose(amount: float) -> void:
	health = maxf(0.0, health - amount)
	if health <= 0.0 and not dead:
		dead = true
		died.emit()


func revive(fraction: float) -> void:
	dead = false
	health = maxf(1.0, MAX_HEALTH * fraction)
	statuses.clear()
	energy = energy_max
	food_zero_hours = 0.0
	water_zero_hours = 0.0
	_warned.clear()


func to_dict() -> Dictionary:
	return {"health": health, "energy": energy, "statuses": statuses.to_dict(), "satiety": satiety,
		"hydration": hydration, "food_zero_hours": food_zero_hours, "water_zero_hours": water_zero_hours}


func load_dict(data: Dictionary) -> void:
	## Eski kayitta tokluk/hidrasyon yoksa GUVENLI varsayilan (80): yuklenen
	## oyuncu ilk saniyede aclik cezasi yemez.
	health = clampf(float(data.get("health", MAX_HEALTH)), 1.0, MAX_HEALTH)
	energy = clampf(float(data.get("energy", BASE_ENERGY)), 0.0, BASE_ENERGY)
	statuses.load_dict(data.get("statuses", {}))
	satiety = clampf(float(data.get("satiety", 80.0)), 0.0, 100.0)
	hydration = clampf(float(data.get("hydration", 80.0)), 0.0, 100.0)
	food_zero_hours = maxf(0.0, float(data.get("food_zero_hours", 0.0)))
	water_zero_hours = maxf(0.0, float(data.get("water_zero_hours", 0.0)))
	dead = false
