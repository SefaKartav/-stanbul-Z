class_name Progression
extends RefCounted
## Deneyim, seviye (1-50), beceri puani, BECERI AGACI dugumleri, ustalik
## sayaclari ve eski yetenek/beceri rutbeleri.
##
## Ilerleme SECIMSELDIR: her seviye puan verir, oyuncu puani agacta bir
## dugume harcar (bkz. SkillTree). Deneyim KAYNAKLARI ayri izlenir (denge
## raporu): oldurme, ilk arama, gorev, kesif, uretim, kurtarma.
## SOMURU KORUMALARI
##   * Ayni dolabin yeniden aranmasi (yenilenme) deneyim vermez.
##   * Uretim: bir tarifin ILK uretimi 3 kat; ayni tarifin tekrarinda
##     deneyim azalir (1 / (1 + n/5)). Uret-sok-uret dongusu doymaz.
##   * Gorev odulu gorev tamamlanmasiyla ayni adimda yazilir (QuestSystem).

signal leveled(level: int, points: int)

const KILL_XP := {"walker": 10.0, "runner": 16.0, "spitter": 20.0, "brute": 45.0}
const DEFAULT_KILL_XP := 10.0
const LOOT_XP_PER_CONTAINER := 12.0
const CRAFT_XP_PER_TIER := 8.0
const MAX_RANK := 5
const POINTS_PER_LEVEL := 1
const REGION_XP := 150.0

var xp := 0.0
var level := 1
var points := 1                   # oyuncu ilk dugumunu hemen alabilsin
var ranks: Dictionary = {}        # ESKI beceri/yetenek rutbeleri (gocle puana cevrilir)
var nodes: Dictionary = {}        # agac dugumu -> true
var counters: Dictionary = {}     # ustalik sayaclari (water_purified, kills_melee, ...)
var sources: Dictionary = {}      # kaynak -> toplam deneyim
var crafted_by_recipe: Dictionary = {}
var regions_seen: Dictionary = {}
var last_respec_day := -100
var total_kills := 0
var total_crafted := 0
var containers_looted := 0
var migrated_points := 0          # eski rutbelerden iade edilen puan (bilgi)


static func max_level() -> int:
	return int(Content.skill_tree.get("max_level", 50)) if not Content.skill_tree.is_empty() else 50


static func xp_for_level(p_level: int) -> float:
	## Veri gudumlu karesel egri: a + b*L + c*L^2 (skill_tree.json xp_curve).
	var curve: Array = Content.skill_tree.get("xp_curve", [80, 30, 2.2]) if not Content.skill_tree.is_empty() else [80, 30, 2.2]
	return float(curve[0]) + float(curve[1]) * p_level + float(curve[2]) * p_level * p_level


static func total_xp_to(p_level: int) -> float:
	var total := 0.0
	for l in range(1, p_level):
		total += xp_for_level(l)
	return total


func xp_needed() -> float:
	return xp_for_level(level)


func award(amount: float) -> int:
	return award_source(amount, "other")


func award_source(amount: float, source: String) -> int:
	sources[source] = float(sources.get(source, 0.0)) + amount
	if level >= max_level():
		return 0
	xp += amount
	var gained := 0
	while level < max_level() and xp >= xp_needed():
		xp -= xp_needed()
		level += 1
		points += POINTS_PER_LEVEL
		gained += 1
	if level >= max_level():
		xp = 0.0
	if gained > 0:
		leveled.emit(level, points)
	return gained


func count(counter: String, amount: int = 1) -> void:
	counters[counter] = int(counters.get(counter, 0)) + amount


func on_kill(zombie_id: String, melee: bool = false) -> void:
	total_kills += 1
	count("kills_melee" if melee else "kills_firearm")
	award_source(float(KILL_XP.get(zombie_id, DEFAULT_KILL_XP)), "kill")


func on_loot() -> void:
	## YALNIZCA ilk arama (yenilenme deneyim vermez; bkz. Game).
	containers_looted += 1
	count("containers_searched")
	award_source(LOOT_XP_PER_CONTAINER, "search")


func on_corpse() -> void:
	award_source(4.0, "search")


func on_craft(tier: int, recipe_id: String = "") -> void:
	total_crafted += 1
	count("crafted")
	var n := int(crafted_by_recipe.get(recipe_id, 0))
	crafted_by_recipe[recipe_id] = n + 1
	var base := CRAFT_XP_PER_TIER * maxi(1, tier)
	var amount := base * 3.0 if n == 0 else base / (1.0 + n / 5.0)
	award_source(maxf(1.0, amount), "craft")


func on_region(region_id: String) -> bool:
	if regions_seen.has(region_id):
		return false
	regions_seen[region_id] = true
	award_source(REGION_XP, "discovery")
	return true


func rank_of(id: String) -> int:
	## Aktif yetenek rutbesi: 1 + agac dugumlerinden gelen artis.
	return mini(MAX_RANK, int(ranks.get(id, 1)) + SkillTree.power_bonus(nodes, id))


func can_upgrade(id: String) -> bool:
	return SkillTree.check(id, self)[0]


func upgrade(id: String) -> bool:
	## Agac dugumunu acar (puani harcar). Tarif acilisi Game tarafinda.
	var ok: Array = SkillTree.check(id, self)
	if not ok[0]:
		return false
	points -= int(SkillTree.node(id).get("cost", 1))
	nodes[id] = true
	return true


func spent_points() -> int:
	var total := 0
	for id: String in nodes:
		total += int(SkillTree.node(id).get("cost", 1))
	return total


func respec(day: int) -> String:
	## Kontrollu puan iadesi: tum dugumler geri alinir, puan iade edilir;
	## bedeli mevcut seviyenin deneyiminin yarisi ve 3 gunde bir.
	var rule: Dictionary = Content.skill_tree.get("respec", {})
	if day - last_respec_day < int(rule.get("cooldown_days", 3)):
		return "Puan iadesi %d gunde bir yapilir" % int(rule.get("cooldown_days", 3))
	if nodes.is_empty():
		return "Iade edilecek dugum yok"
	points += spent_points()
	nodes.clear()
	xp *= 1.0 - float(rule.get("cost_xp_ratio", 0.5))
	last_respec_day = day
	return ""


func to_dict() -> Dictionary:
	return {"xp": xp, "level": level, "points": points, "ranks": ranks.duplicate(), "nodes": nodes.keys(),
		"counters": counters.duplicate(), "sources": sources.duplicate(), "crafted_by_recipe": crafted_by_recipe.duplicate(),
		"regions_seen": regions_seen.keys(), "last_respec_day": last_respec_day,
		"total_kills": total_kills, "total_crafted": total_crafted, "containers_looted": containers_looted,
		"tree_version": 1}


func load_dict(data: Dictionary) -> void:
	xp = float(data.get("xp", 0.0))
	level = clampi(int(data.get("level", 1)), 1, max_level())
	points = maxi(0, int(data.get("points", 0)))
	ranks.clear()
	for key: String in data.get("ranks", {}):
		ranks[key] = clampi(int(data.ranks[key]), 1, MAX_RANK)
	nodes.clear()
	for id: Variant in data.get("nodes", []):
		if not SkillTree.node(str(id)).is_empty():
			nodes[str(id)] = true
	counters = data.get("counters", {}).duplicate()
	sources = data.get("sources", {}).duplicate()
	crafted_by_recipe = data.get("crafted_by_recipe", {}).duplicate()
	regions_seen.clear()
	for r: Variant in data.get("regions_seen", []):
		regions_seen[str(r)] = true
	last_respec_day = int(data.get("last_respec_day", -100))
	total_kills = int(data.get("total_kills", 0))
	total_crafted = int(data.get("total_crafted", 0))
	containers_looted = int(data.get("containers_looted", 0))
	# GOC: agac oncesi kayit (tree_version yok). Eski beceri/yetenek
	# rutbelerine harcanan puan KAYBOLMAZ: puan olarak iade edilir, rutbeler
	# temel degere doner; oyuncu puanlari agacta yeniden dagitir.
	migrated_points = 0
	if not data.has("tree_version"):
		for key: String in ranks:
			migrated_points += int(ranks[key]) - 1
		ranks.clear()
		points += migrated_points
		if not counters.has("containers_searched"):
			counters["containers_searched"] = containers_looted
			counters["crafted"] = total_crafted
			counters["kills_firearm"] = total_kills
