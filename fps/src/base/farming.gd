class_name Farming
extends RefCounted
## Saksi ve tarla (yerlestirilebilir "planter") ekimi.
##
## EKIN (world/crops.json): tohum -> {yield, count [min,max], hours, water_per_day,
## seed_return}. Buyume OYUN SAATIYLE ilerler ve SU ister: saksidaki su
## birimi gunluk ihtiyaca gore azalir; su bitince buyume DURUR (kurumaz ama
## beklemez de -- oyuncu sulamayi unutursa hasat gecikir). Kirli su da
## sulamaya uygundur (bitki kaynatilmis su istemez).
##   * Gubre (etiket "fertilizer"): o ekim icin buyume x1.5.
##   * Hidroponik saksi (catalog "power" > 0): ELEKTRIK varsa x1.6 hiz, yarim su.
##   * Koloni: ussun icindeki saksilari, usteki CIFTCI her gun depodaki suyla sular.
## Hasat urunu verir; tohum geri donusu olasiliklidir (sonsuz tohum yok).

const WATER_ITEMS := ["water_dirty", "water_bottle", "water_canister", "water_pouch"]
const WATER_UNITS := {"water_dirty": 1.0, "water_bottle": 1.0, "water_canister": 5.0, "water_pouch": 0.25}
const MAX_WATER := 6.0


static func crop(seed_id: String) -> Dictionary:
	return Content.crops.get(seed_id, {})


static func status_text(entry: Dictionary) -> String:
	var s: Dictionary = entry.state
	var seed := str(s.get("seed", ""))
	if seed == "":
		return "boş"
	var c := crop(seed)
	var ready := float(s.get("growth", 0.0)) >= 1.0
	var name: String = Content.item(str(c.get("yield", ""))).name if Content.item(str(c.get("yield", ""))) != null else seed
	if ready:
		return "%s hasada hazır" % name
	return "%s %%%d · su %.1f" % [name, int(float(s.growth) * 100.0), float(s.get("water", 0.0))]


static func tick(entry: Dictionary, hours: float) -> void:
	var s: Dictionary = entry.state
	var seed := str(s.get("seed", ""))
	if seed == "" or float(s.get("growth", 0.0)) >= 1.0:
		return
	var c := crop(seed)
	if c.is_empty():
		return
	var info: Dictionary = Content.placeables.get(entry.item_id, {})
	var hydro := float(info.get("power", 0.0)) > 0.0
	if hydro and not bool(entry.powered):
		return
	var need := float(c.get("water_per_day", 1.0)) * hours / 24.0 * (0.5 if hydro else 1.0)
	if float(s.get("water", 0.0)) < need:
		return
	s.water = float(s.water) - need
	var rate := hours / maxf(1.0, float(c.get("hours", 48.0)))
	rate *= float(info.get("growth", 1.0))
	if hydro:
		rate *= 1.6
	if bool(s.get("fertilized", false)):
		rate *= 1.5
	s.growth = minf(1.0, float(s.growth) + rate)


static func interact(entry: Dictionary, inventory: Inventory, rng: RandomNumberGenerator, skills: SkillProfile) -> String:
	## E: bos saksiya ekim; buyurken once gubre, sonra sulama; olgunsa hasat.
	var s: Dictionary = entry.state
	var seed := str(s.get("seed", ""))
	if seed == "":
		for stack: ItemStack in inventory.stacks:
			if Content.crops.has(stack.definition.id):
				var taken := inventory.take_from_stack(stack, 1)
				if taken == null:
					break
				s.seed = stack.definition.id
				s.growth = 0.0
				s.fertilized = false
				s.quality = clampf(taken.quality if taken.definition.has_quality else 50.0, 20.0, 90.0)
				return "Ekildi: %s. Sulamayı unutma (E)." % taken.definition.name
		return "Ekecek tohum yok (tohumlar dolap, market ve bahçelerde bulunur)"
	if float(s.get("growth", 0.0)) >= 1.0:
		return harvest(entry, inventory, rng, skills)
	if not bool(s.get("fertilized", false)):
		var fert := inventory.matching_tag("fertilizer")
		if not fert.is_empty():
			inventory.take_from_stack(fert[0], 1)
			s.fertilized = true
			return "Gübre verildi: büyüme hızlandı"
	if float(s.get("water", 0.0)) >= MAX_WATER - 0.5:
		return "Toprak nemli. %s" % status_text(entry)
	for item_id: String in WATER_ITEMS:
		var stack := inventory.find(item_id)
		if stack == null:
			continue
		var back := str(Content.nutrition_of(item_id).get("returns", ""))
		var trial := inventory.clone()
		trial.take_from_stack(trial.stacks[inventory.stacks.find(stack)], 1)
		if back != "" and trial.add(ItemStack.new(Content.item(back), 1, 0.0)) > 0:
			return "Boş şişe için yer yok"
		inventory.replace_with(trial)
		s.water = minf(MAX_WATER, float(s.get("water", 0.0)) + float(WATER_UNITS.get(item_id, 1.0)))
		return "Sulandı (%s). %s" % [Content.item(item_id).name, status_text(entry)]
	return "Sulamak için su yok (kirli su da olur). %s" % status_text(entry)


static func harvest(entry: Dictionary, inventory: Inventory, rng: RandomNumberGenerator, skills: SkillProfile) -> String:
	var s: Dictionary = entry.state
	var seed := str(s.seed)
	var c := crop(seed)
	var counts: Array = c.get("count", [2, 3])
	var amount := rng.randi_range(int(counts[0]), int(counts[1]))
	if skills != null and skills.has_behavior("green_thumb"):
		amount += 1
	var produce := ItemStack.new(Content.item(str(c.yield)), amount, float(s.get("quality", 50.0)))
	var trial := inventory.clone()
	if trial.add(produce.copy()) > 0:
		return "Hasat için çantada yer yok"
	var seeds_back := 0
	if rng.randf() < float(c.get("seed_return", 0.5)):
		seeds_back = 1
		if trial.add(ItemStack.new(Content.item(seed), 1, 50.0)) > 0:
			seeds_back = 0
	inventory.replace_with(trial)
	s.seed = ""
	s.growth = 0.0
	s.fertilized = false
	return "Hasat: %d× %s%s" % [amount, produce.definition.name, " (+1 tohum)" if seeds_back > 0 else ""]


static func colony_water(base: Settlement, planters: Array) -> int:
	## Usteki ciftci: ussun icindeki saksilari depodaki suyla sular.
	var watered := 0
	for entry: Dictionary in planters:
		var s: Dictionary = entry.state
		if str(s.get("seed", "")) == "" or float(s.get("water", 0.0)) >= MAX_WATER - 1.0:
			continue
		for item_id: String in WATER_ITEMS:
			if base.stockpile.count(item_id) > 0:
				base.stockpile.remove(item_id, 1)
				var back := str(Content.nutrition_of(item_id).get("returns", ""))
				if back != "":
					base.stockpile.add(ItemStack.new(Content.item(back), 1, 0.0))
				s.water = minf(MAX_WATER, float(s.get("water", 0.0)) + float(WATER_UNITS.get(item_id, 1.0)) * 2.0)
				watered += 1
				break
	return watered
