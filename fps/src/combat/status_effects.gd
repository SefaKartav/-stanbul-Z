class_name StatusEffects
extends RefCounted
## Bir varliktaki aktif durum etkileri (Python: powers/effects.py).
##
## Ayni etkinin ikinci kez uygulanmasi SURE YENILER, ust uste BINMEZ;
## buyuk siddet kucugu ezer. Enfeksiyon kendiliginden GECMEZ: ancak ilac
## ya da ilk yardimla kalkar -- beklemek tip becerisini anlamsiz kilardi.

const BURN := "burn"
const SLOW := "slow"
const BLEED := "bleed"
const INFECTION := "infection"
const FRACTURE := "fracture"
const ARMOR_BREAK := "armor_break"
const ADRENALINE := "adrenaline"
const SICK := "sick"          # kirli su / bozuk yemek: hidrasyon kaybi, nefes tavani
const REGEN := "regen"        # ilac/yemek: sure boyunca saniyede `magnitude` can
const FORTIFIED := "fortified"  # alinan hasar x (1 - magnitude)
const FOCUS := "focus"        # namlu dagilmasi x (1 - magnitude)

const DOT := {BURN: "fire", BLEED: "physical", INFECTION: "physical"}
const PERSISTENT := [INFECTION]
const LABELS := {BURN: "Yanıyor", SLOW: "Yavaş", BLEED: "Kanama", INFECTION: "Enfeksiyon",
	FRACTURE: "Kırık", ARMOR_BREAK: "Zırh kırık", ADRENALINE: "Adrenalin", SICK: "Mide bulantısı",
	REGEN: "İyileşiyor", FORTIFIED: "Dirençli", FOCUS: "Odaklı"}

# tur -> {remaining, magnitude}
var active: Dictionary = {}


func apply(kind: String, duration: float, magnitude: float) -> void:
	if active.has(kind):
		var current: Dictionary = active[kind]
		current.remaining = maxf(current.remaining, duration)
		current.magnitude = maxf(current.magnitude, magnitude)
	else:
		active[kind] = {"remaining": duration, "magnitude": magnitude}


func has(kind: String) -> bool:
	return active.has(kind)


func remove(kind: String) -> void:
	active.erase(kind)


func clear() -> void:
	active.clear()


func tick(delta: float, resistance: float = 0.0) -> float:
	## Sureleri ilerletir; bu adimda alinacak toplam DoT hasarini dondurur.
	## `resistance` (0..1) tip becerisinden: DoT'yi azaltir, sureyi kisaltir.
	var damage := 0.0
	for kind: String in active.keys():
		var status: Dictionary = active[kind]
		if DOT.has(kind):
			damage += status.magnitude * delta * (1.0 - clampf(resistance, 0.0, 0.8))
		if kind in PERSISTENT:
			continue
		status.remaining -= delta * (1.0 + resistance)
		if status.remaining <= 0.0:
			active.erase(kind)
	return damage


func speed_multiplier() -> float:
	var multiplier := 1.0
	if active.has(SLOW):
		multiplier *= maxf(0.15, 1.0 - active[SLOW].magnitude)
	if active.has(FRACTURE):
		multiplier *= maxf(0.35, 1.0 - active[FRACTURE].magnitude)
	if active.has(ADRENALINE):
		multiplier *= 1.0 + active[ADRENALINE].magnitude
	return multiplier


func damage_taken_multiplier() -> float:
	var m: float = 1.0 + (float(active[ARMOR_BREAK].magnitude) if active.has(ARMOR_BREAK) else 0.0)
	if active.has(FORTIFIED):
		m *= maxf(0.3, 1.0 - float(active[FORTIFIED].magnitude))
	return m


func regen_rate() -> float:
	return float(active[REGEN].magnitude) if active.has(REGEN) else 0.0


func spread_multiplier() -> float:
	return maxf(0.4, 1.0 - float(active[FOCUS].magnitude)) if active.has(FOCUS) else 1.0


func labels() -> PackedStringArray:
	var result := PackedStringArray()
	for kind: String in active:
		result.append(LABELS.get(kind, kind))
	return result


func to_dict() -> Dictionary:
	return active.duplicate(true)


func load_dict(data: Dictionary) -> void:
	active.clear()
	for kind: String in data:
		var entry: Variant = data[kind]
		if typeof(entry) == TYPE_DICTIONARY and LABELS.has(kind):
			active[kind] = {"remaining": float(entry.get("remaining", 0.0)),
				"magnitude": float(entry.get("magnitude", 0.0))}
