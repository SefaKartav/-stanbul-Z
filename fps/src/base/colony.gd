class_name Colony
extends RefCounted
## Kalici sakin kayitlari ve gunluk isler; fiziksel NPC'lerden BAGIMSIZDIR
## (Python: game/base/colony.py -- kurallar birebir).
##
## Gunluk simulasyon SOYUTTUR ve tek gun sinirini bir kez isler:
## `advance_day` ayni gun icin tekrar cagrilirsa hicbir sey yapmaz. Uzak
## ussun soyut uretimi ile yakindaki NPC'nin gorunen isi AYNI kaydi
## kullanir; iki ayri uretim kaynagi yoktur (cift uretim olusamaz).

const MIN_EXPEDITION_DANGER := 0.35
const SHOOTING_DANGER_RELIEF := 0.05
const FORAGING_LUCK := 0.04
const MAX_EXPEDITION_LUCK := 0.5
const INJURY_MORALE_LOSS := 20
const RETURN_MORALE_GAIN := 10
const MAX_REPORTED_ITEMS := 5
const MAX_COMPLETED_EXPEDITIONS := 5
const DEFAULT_BOND_GAIN := 0.06
const DEFAULT_BOND_LOSS := 0.10
const DEFAULT_BOND_MORALE := 6.0
const BOND_STRAIN_MORALE := 30
const DEFAULT_LEAVE_THRESHOLD := 15
const DEFAULT_LEAVE_DAYS := 4
const DEFAULT_LEAVE_TAKES_DAYS := 2
const DEFAULT_LEAVE_MIN_HEALTH := 40
const DEFAULT_MORALE_CEILING := 80.0
const FIELD_SIDE_CELLS := 4          # eski 2 karo x 2 m

var data: Dictionary
var settings: Dictionary
var bases: Array = []                # Settlement listesi (BaseSystem ile paylasilir)
var residents: Dictionary = {}       # id -> sakin sozlugu
var last_day := 1
var fields: Array = []
var expeditions: Array = []
var next_expedition_id := 1
var day_events: Array = []
var rng := RandomNumberGenerator.new()
var work_orders := WorkOrders.new()
var crafting: CraftingService
var station_tier := 3
var colony_skills := SkillProfile.new()


func _init(p_bases: Array, seed_value: int = 20260909) -> void:
	data = Content.colony
	settings = data.get("settings", {})
	bases = p_bases
	rng.seed = seed_value
	crafting = CraftingService.new(Content.items, seed_value + 1)


static func new_resident(profile_id: String, settlement_id: String) -> Dictionary:
	var profile: Dictionary = Content.colony.profiles[profile_id]
	var cfg: Dictionary = Content.colony.settings
	return {"id": profile_id, "settlement_id": settlement_id, "name": profile.name,
		"background": profile.background, "skills": profile.skills.duplicate(),
		"role": "idle", "health": float(cfg.health), "morale": float(cfg.initial_morale),
		"hunger": 0.0, "thirst": 0.0, "fatigue": 0.0, "work_credit": 0.0,
		"status": "colony.resting", "relationships": {}, "low_morale_days": 0}


func base_by_id(settlement_id: String) -> Settlement:
	for base: Settlement in bases:
		if base.id == settlement_id:
			return base
	return null


func members(settlement_id: String, alive_only: bool = true) -> Array:
	var result: Array = []
	for r: Dictionary in residents.values():
		if r.settlement_id == settlement_id and (not alive_only or r.health > 0):
			result.append(r)
	return result


func candidates() -> Array:
	var result: Array = []
	for key: String in data.get("profiles", {}):
		if not residents.has(key):
			result.append(key)
	return result


func recruit(base: Settlement, profile_id: String) -> String:
	if not bases.has(base) or base.breached:
		return "colony.unsafe"
	if not candidates().has(profile_id):
		return "colony.unavailable"
	var capacity := int(base.capacity("dorm"))
	if members(base.id).size() >= capacity:
		return "colony.no_beds"
	residents[profile_id] = new_resident(profile_id, base.id)
	sync_population()
	return "colony.recruited"


func assign(resident_id: String, role: String) -> String:
	var r: Dictionary = residents.get(resident_id, {})
	if r.is_empty() or r.health <= 0 or not data.roles.has(role):
		return "colony.unavailable"
	r.role = role
	r.work_credit = 0.0
	r.status = "colony.assigned"
	return r.status


func sync_population() -> void:
	for base: Settlement in bases:
		base.population = 1 + members(base.id).size()


# --- tarim ---
func plant(base: Settlement) -> String:
	## Uygun ilk acik parseli secer; tohum yalnizca basarida tuketilir.
	var cfg: Dictionary = data.farming
	if not bases.has(base) or base.breached:
		return "colony.unsafe"
	if base.stockpile.count(cfg.seed) < int(cfg.seed_count):
		return "colony.no_seed"
	var occupied := {}
	for plot: Dictionary in fields:
		for dz in FIELD_SIDE_CELLS:
			for dx in FIELD_SIDE_CELLS:
				occupied[Vector2i(plot.tile[0] + dx, plot.tile[1] + dz)] = true
	var cells := base.interior.keys()
	cells.sort()
	for cell: Vector2i in cells:
		var ok := true
		for dz in FIELD_SIDE_CELLS:
			for dx in FIELD_SIDE_CELLS:
				var c := Vector2i(cell.x + dx, cell.y + dz)
				if not base.interior.has(c) or occupied.has(c):
					ok = false
		if ok:
			base.stockpile.remove(cfg.seed, int(cfg.seed_count))
			fields.append({"settlement_id": base.id, "tile": [cell.x, cell.y], "growth": 0,
				"last_day": last_day, "quality": 50})
			return "colony.planted"
	return "colony.no_space"


func harvest(base: Settlement) -> String:
	## Hazir tarlalari toplar; urunle birlikte TOHUM da doner (dongu kapanir).
	var cfg: Dictionary = data.farming
	var ready := fields.filter(func(p: Dictionary) -> bool:
		return p.settlement_id == base.id and p.growth >= int(cfg.growth_days))
	if ready.is_empty():
		return "colony.not_ready"
	var seed_return := int(cfg.get("seed_return", 0))
	for plot: Dictionary in ready:
		var trial := base.stockpile.clone()
		if trial.add(ItemStack.new(Content.item(cfg.yield_item), int(cfg.yield_count), float(plot.get("quality", 50)))) > 0:
			return "colony.stock_full"
		if seed_return > 0:
			trial.add(ItemStack.new(Content.item(cfg.seed), seed_return))
		base.stockpile.replace_with(trial)
		fields.erase(plot)
	return "colony.harvested"


func _farm(base: Settlement, resident: Dictionary) -> void:
	var cfg: Dictionary = data.farming
	var water: Dictionary = Content.resources.get_resource("water")
	var limit := maxi(1, int(cfg.get("fields_per_day", 1)))
	var tended := 0
	for plot: Dictionary in fields:
		if tended >= limit:
			break
		if plot.settlement_id != base.id:
			continue
		if plot.growth >= int(cfg.growth_days) or int(plot.last_day) >= last_day:
			continue
		if Content.resources.stock(base.stockpile, water) < float(cfg.water_daily):
			resident.status = "colony.no_water"
			return
		Content.resources.consume(base.stockpile, water, float(cfg.water_daily))
		plot.growth = mini(int(cfg.growth_days), int(plot.growth) + 1)
		plot.last_day = last_day
		plot.quality = mini(100, 50 + int(resident.skills.get("farming", 0)) * int(cfg.quality_per_skill))
		tended += 1
	if tended == 0:
		resident.status = "colony.no_field"
		return
	resident.fatigue = minf(100.0, resident.fatigue + float(settings.fatigue_gain))
	resident.status = "colony.tended"


# --- gunluk dongu ---
func advance_day(day: int, shortages: Dictionary) -> void:
	## Tek gunluk siniri isler; ayni gun icin tekrar cagrilmak isi COGALTMAZ.
	if day <= last_day:
		return
	last_day = day
	day_events = []
	_resolve_expeditions()
	for base: Settlement in bases:
		var missing: Dictionary = shortages.get(base.id, {})
		for resident: Dictionary in members(base.id):
			if resident.status != "colony.expedition":
				_needs(resident, missing)
			_work(base, resident)
		_socialise(base, missing)
		_check_departures(base)
	sync_population()


func _socialise(base: Settlement, missing: Dictionary) -> void:
	var gain := float(settings.get("bond_gain", DEFAULT_BOND_GAIN))
	var loss := float(settings.get("bond_loss", DEFAULT_BOND_LOSS))
	var weight := float(settings.get("bond_morale", DEFAULT_BOND_MORALE))
	var crew := members(base.id)
	var hard_day := not missing.is_empty() or base.breached
	for i in crew.size():
		for j in range(i + 1, crew.size()):
			var first: Dictionary = crew[i]
			var second: Dictionary = crew[j]
			var delta := -loss if hard_day or minf(first.morale, second.morale) < BOND_STRAIN_MORALE else gain
			for pair: Array in [[first, second], [second, first]]:
				var a: Dictionary = pair[0]
				var b: Dictionary = pair[1]
				a.relationships[b.id] = clampf(float(a.relationships.get(b.id, 0.0)) + delta, -1.0, 1.0)
	# Asimetrik geri besleme: husumet morali ceker, dostluk TAVANI yukseltir.
	for resident: Dictionary in crew:
		var penalty := weight * minf(0.0, _average_bond(resident))
		if penalty != 0.0:
			resident.morale = clampf(resident.morale + penalty, 0.0, 100.0)


static func _average_bond(resident: Dictionary) -> float:
	var bonds: Dictionary = resident.relationships
	if bonds.is_empty():
		return 0.0
	var total := 0.0
	for value: float in bonds.values():
		total += value
	return total / bonds.size()


func _check_departures(base: Settlement) -> void:
	## Morali dipte kalan sakin uzun surede ussu TERK EDER ve erzak goturur.
	## Gitmeye gucu yetmeyen (cani dusuk) gidemez -- kalir ve olur.
	var threshold := float(settings.get("leave_threshold", DEFAULT_LEAVE_THRESHOLD))
	var patience := int(settings.get("leave_days", DEFAULT_LEAVE_DAYS))
	var floor_health := float(settings.get("leave_min_health", DEFAULT_LEAVE_MIN_HEALTH))
	for resident: Dictionary in members(base.id):
		if resident.morale > threshold:
			resident.low_morale_days = 0
			continue
		resident.low_morale_days = int(resident.low_morale_days) + 1
		if resident.health <= floor_health:
			continue
		if resident.low_morale_days < patience:
			if resident.low_morale_days == patience - 1:
				day_events.append("%s gitmekten soz ediyor." % resident.name)
			continue
		_depart(base, resident)


func _depart(base: Settlement, resident: Dictionary) -> void:
	var taken := 0
	var days := int(settings.get("leave_takes_days", DEFAULT_LEAVE_TAKES_DAYS))
	for resource_id: String in ["food", "water"]:
		var resource: Dictionary = Content.resources.get_resource(resource_id)
		if resource.is_empty():
			continue
		var amount := float(settings.get(resource_id + "_daily", 1.0)) * days
		taken += int(Content.resources.consume(base.stockpile, resource, amount)[0])
	residents.erase(resident.id)
	for other: Dictionary in residents.values():
		other.relationships.erase(resident.id)
	var note := "%s ussu terk etti" % resident.name
	day_events.append("%s (%d erzak goturdu)." % [note, taken] if taken > 0 else note + ".")


func _morale_ceiling(resident: Dictionary) -> float:
	var base_ceiling := float(settings.get("morale_ceiling", DEFAULT_MORALE_CEILING))
	base_ceiling *= colony_skills.multiplier("colony_morale")
	var weight := float(settings.get("bond_morale", DEFAULT_BOND_MORALE))
	return clampf(base_ceiling + weight * maxf(0.0, _average_bond(resident)), 0.0, 100.0)


func _needs(resident: Dictionary, missing: Dictionary) -> void:
	for pair: Array in [["hunger", "food"], ["thirst", "water"]]:
		var change := float(settings.need_gain) if missing.has(pair[1]) else -float(settings.need_recovery)
		resident[pair[0]] = clampf(float(resident[pair[0]]) + change, 0.0, 100.0)
	if missing.has("food") or missing.has("water"):
		resident.morale = maxf(0.0, resident.morale - float(settings.morale_loss))
	else:
		# KONFOR TAVANI: tok olmak morali ancak tavana kadar tasir.
		var ceiling := _morale_ceiling(resident)
		if resident.morale > ceiling:
			resident.morale = maxf(ceiling, resident.morale - float(settings.morale_recovery))
		else:
			resident.morale = minf(ceiling, resident.morale + float(settings.morale_recovery))
	resident.morale = clampf(resident.morale, 0.0, 100.0)
	if maxf(resident.hunger, resident.thirst) >= float(settings.need_damage_threshold):
		resident.health = maxf(0.0, resident.health - float(settings.starvation_damage))


func _work(base: Settlement, resident: Dictionary) -> void:
	if resident.health <= 0:
		resident.status = "colony.dead"
		return
	if resident.role == "idle" or resident.fatigue >= float(settings.rest_threshold):
		resident.fatigue = maxf(0.0, resident.fatigue - float(settings.rest_recovery))
		resident.status = "colony.resting"
		return
	var job: Dictionary = data.roles[resident.role]
	if base.breached:
		resident.status = "colony.unsafe"
		return
	if job.building != "none" and not base.has_role(job.building):
		resident.status = "colony.no_workplace"
		return
	match resident.role:
		"expedition":
			resident.status = "colony.expedition"
			return
		"farmer":
			_farm(base, resident)
			return
		"guard":
			resident.status = "colony.guarding"
			resident.fatigue = minf(100.0, resident.fatigue + float(settings.fatigue_gain))
			return
	var efficiency := 1.0 + float(resident.skills.get(job.skill, 0)) / float(settings.skill_divisor)
	efficiency *= resident.morale / 100.0
	efficiency *= 1.0 - maxf(resident.hunger, resident.thirst) / 100.0
	efficiency *= colony_skills.multiplier("colony_output")
	resident.work_credit = minf(float(settings.max_work_credit), resident.work_credit + efficiency)
	if resident.work_credit < float(settings.work_threshold):
		resident.status = "colony.working"
		return
	var patients := members(base.id).filter(func(r: Dictionary) -> bool: return r.health < float(settings.health))
	if resident.role == "doctor" and patients.is_empty():
		resident.status = "colony.no_patient"
		return
	# IS EMRI ONCELIKLIDIR: oyuncu "on bandaj" dediyse zanaatkar onu yapar.
	if resident.role == "crafter" and _craft_from_orders(base, resident):
		return
	for key: String in job.inputs:
		if base.stockpile.count(key) < int(job.inputs[key]):
			resident.status = "colony.no_materials"
			return
	# Once kopyada dene: depo doluysa ne girdiler ne uretim kaybolur.
	var trial := base.stockpile.clone()
	for key: String in job.inputs:
		trial.remove(key, int(job.inputs[key]))
	for key: String in job.outputs:
		if trial.add(ItemStack.new(Content.item(key), int(job.outputs[key]))) > 0:
			resident.status = "colony.stock_full"
			return
	base.stockpile.replace_with(trial)
	if resident.role == "doctor":
		patients.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.health < b.health)
		var patient: Dictionary = patients[0]
		patient.health = minf(float(settings.health), patient.health + float(settings.doctor_heal))
	resident.work_credit -= float(settings.work_threshold)
	resident.fatigue = minf(100.0, resident.fatigue + float(settings.fatigue_gain))
	resident.status = "colony.completed"


func _craft_from_orders(base: Settlement, resident: Dictionary) -> bool:
	## Zanaatkar bir is emrinden gunde TEK adet uretir: koloni bir dugme
	## degil bir EKIPTIR. Girdiler depodan GERCEKTEN harcanir.
	var order := work_orders.next_for(base.id)
	if order.is_empty():
		return false
	var recipe: RecipeDef = Content.recipes.get(order.recipe_id)
	if recipe == null:
		order.blocked = "workorder.unknown_recipe"
		resident.status = "colony.no_materials"
		return true
	var result := crafting.craft(base.stockpile, recipe, recipe.station, station_tier,
		float(resident.skills.get("repair", 0)))
	if not result.success:
		order.blocked = result.reason if result.reason != "" else "workorder.blocked"
		resident.status = "colony.no_materials"
		return true
	order.blocked = ""
	order.done += 1
	resident.work_credit -= float(settings.work_threshold)
	resident.fatigue = minf(100.0, resident.fatigue + float(settings.fatigue_gain))
	resident.status = "colony.completed"
	if order.done >= order.quantity:
		day_events.append("%s: %s emri tamamlandi." % [resident.name, recipe.name])
	return true


# --- seferler ---
func launch_expedition(base: Settlement, region_id: String, member_ids: Array) -> String:
	## Azik CIKISTA alinir: "bu seferi kaldirabilir miyim?" karari gorunur.
	var cfg: Dictionary = data.get("expedition", {})
	if not bases.has(base) or base.breached:
		return "colony.unsafe"
	if not Content.regions.has(region_id):
		return "colony.invalid_region"
	var valid: Array = []
	for rid: String in member_ids:
		var r: Dictionary = residents.get(rid, {})
		if not r.is_empty() and r.settlement_id == base.id and r.health > 0:
			valid.append(rid)
	if valid.is_empty():
		return "colony.no_members"
	var duration := maxi(1, int(cfg.get("duration_days", 1)))
	if not _take_supplies(base, cfg, valid.size(), duration):
		return "colony.no_supplies"
	for rid: String in valid:
		residents[rid].role = "expedition"
		residents[rid].status = "colony.expedition"
	expeditions.append({"id": "exp%d" % next_expedition_id, "settlement_id": base.id,
		"region_id": region_id, "start_day": last_day, "duration": duration,
		"members": valid, "status": "active", "report": "", "reported": false})
	next_expedition_id += 1
	return "colony.expedition_launched"


func _take_supplies(base: Settlement, cfg: Dictionary, people: int, days: int) -> bool:
	var wanted: Array = []
	for resource_id: String in ["food", "water"]:
		var amount := float(cfg.get(resource_id + "_daily", 0)) * people * days
		if amount <= 0.0:
			continue
		var resource: Dictionary = Content.resources.get_resource(resource_id)
		if resource.is_empty():
			continue
		if Content.resources.stock(base.stockpile, resource) < amount:
			return false
		wanted.append([resource, amount])
	for entry: Array in wanted:
		Content.resources.consume(base.stockpile, entry[0], entry[1])
	return true


func expedition_cost(people: int) -> Dictionary:
	var cfg: Dictionary = data.get("expedition", {})
	var days := maxi(1, int(cfg.get("duration_days", 1)))
	return {"food": float(cfg.get("food_daily", 0)) * people * days,
		"water": float(cfg.get("water_daily", 0)) * people * days}


func _resolve_expeditions() -> void:
	## Suresi dolan seferler SOYUT cozulur ama sonuc OKUNABILIR olmali.
	var cfg: Dictionary = data.get("expedition", {})
	for exp: Dictionary in expeditions:
		if exp.status != "active" or last_day < int(exp.start_day) + int(exp.duration):
			continue
		var base := base_by_id(exp.settlement_id)
		var region: Dictionary = Content.regions.get(exp.region_id, {})
		var danger_mult := float(region.get("danger_multiplier", 1.0))
		var loot_mult := float(region.get("loot_multiplier", 1.0))
		var team: Array = []
		for rid: String in exp.members:
			if residents.has(rid):
				team.append(residents[rid])
		var foraging := 0
		var shooting := 0
		for r: Dictionary in team:
			foraging += int(r.skills.get("foraging", 0))
			shooting += int(r.skills.get("shooting", 0))
		var danger := danger_mult * (float(cfg.get("base_danger", 1.0))
			+ float(cfg.get("danger_per_day", 0.0)) * (int(exp.duration) - 1))
		danger = maxf(MIN_EXPEDITION_DANGER, danger - shooting * SHOOTING_DANGER_RELIEF)
		var lines := PackedStringArray(["%s seferi tamamlandi." % region.get("name", exp.region_id)])
		var chance := float(cfg.get("injury_chance_base", 0.15)) * danger
		for resident: Dictionary in team:
			if rng.randf() < chance:
				var damage := rng.randi_range(15, 35)
				resident.health = maxf(0.0, resident.health - damage)
				resident.morale = maxf(0.0, resident.morale - INJURY_MORALE_LOSS)
				if resident.health <= 0:
					resident.status = "colony.dead"
					lines.append("%s donmedi." % resident.name)
					continue
				lines.append("%s yaralandi (-%d can)." % [resident.name, damage])
			else:
				resident.morale = minf(100.0, resident.morale + RETURN_MORALE_GAIN)
			resident.role = "idle"
			resident.status = "colony.resting"
		_resolve_loot(base, exp, region, cfg, foraging, loot_mult, lines)
		exp.status = "completed"
		exp.report = " ".join(lines)
	var completed := expeditions.filter(func(e: Dictionary) -> bool: return e.status != "active")
	while completed.size() > MAX_COMPLETED_EXPEDITIONS:
		expeditions.erase(completed.pop_front())


func _resolve_loot(base: Settlement, exp: Dictionary, region: Dictionary, cfg: Dictionary,
		foraging: int, loot_mult: float, lines: PackedStringArray) -> void:
	if base == null or base.breached:
		lines.append("Us guvenli olmadigi icin ganimet getirilemedi.")
		return
	var tables: Array = []
	for table_id: String in region.get("loot_tables", []):
		if Content.loot_tables.has(table_id):
			tables.append(Content.loot_tables[table_id])
	if tables.is_empty():
		lines.append("Bu bolge icin ganimet tablosu tanimli degil.")
		return
	# Yagma oyuncunun kendi aramasiyla AYNI loot sistemini kullanir.
	var rolls := maxi(1, int(float(cfg.get("loot_rolls_per_day", 3)) * int(exp.duration) * loot_mult))
	var luck := minf(MAX_EXPEDITION_LUCK, foraging * FORAGING_LUCK)
	var trial := base.stockpile.clone()
	var brought := {}
	var overflow := false
	for _i in rolls:
		var table: LootTable = tables[rng.randi() % tables.size()]
		for stack: ItemStack in table.roll(Content.items, rng, luck):
			var wanted := stack.quantity
			var left := trial.add(stack)
			if wanted - left > 0:
				brought[stack.definition.name] = int(brought.get(stack.definition.name, 0)) + wanted - left
			if left > 0:
				overflow = true
	base.stockpile.replace_with(trial)
	if brought.is_empty():
		lines.append("Kayda deger ganimet bulunamadi.")
	else:
		var names := brought.keys()
		names.sort_custom(func(a: String, b: String) -> bool: return brought[a] > brought[b])
		var parts := PackedStringArray()
		for name: String in names.slice(0, MAX_REPORTED_ITEMS):
			parts.append("%dx %s" % [brought[name], name])
		lines.append("Getirilen: %s." % ", ".join(parts))
	if overflow:
		lines.append("Depo doldugu icin bir kismi birakildi.")


# --- kalicilik ---
func to_dict() -> Dictionary:
	return {"last_day": last_day, "residents": residents.values().map(func(r: Dictionary) -> Dictionary: return r.duplicate(true)),
		"work_orders": work_orders.to_dict(), "fields": fields.duplicate(true),
		"next_expedition_id": next_expedition_id, "expeditions": expeditions.duplicate(true)}


func load_dict(saved: Dictionary, day: int) -> void:
	var base_ids := bases.map(func(b: Settlement) -> String: return b.id)
	residents.clear()
	for entry: Variant in saved.get("residents", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if not entry.get("settlement_id", "") in base_ids or not data.roles.has(entry.get("role", "")):
			continue
		if not data.profiles.has(entry.get("id", "")):
			continue
		var r: Dictionary = new_resident(entry.id, entry.settlement_id)
		for key: String in r:
			if entry.has(key):
				r[key] = entry[key]
		residents[r.id] = r
	fields = saved.get("fields", []).filter(func(p: Variant) -> bool:
		return typeof(p) == TYPE_DICTIONARY and p.get("settlement_id", "") in base_ids)
	last_day = int(saved.get("last_day", day))
	expeditions = saved.get("expeditions", []).filter(func(e: Variant) -> bool:
		return typeof(e) == TYPE_DICTIONARY and e.get("settlement_id", "") in base_ids)
	next_expedition_id = int(saved.get("next_expedition_id", expeditions.size() + 1))
	work_orders.load_dict(saved.get("work_orders", {}), base_ids, Content.recipes)
	sync_population()
