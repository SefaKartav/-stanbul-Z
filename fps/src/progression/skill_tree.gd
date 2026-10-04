class_name SkillTree
extends RefCounted
## Alti dalli beceri agaci (data/skills/skill_tree.json).
##
## Bir dugum ancak su dordu birlikte saglaninca acilir: yeterli BECERI PUANI,
## ONKOSUL dugum(ler), KARAKTER SEVIYESI ve (varsa) UYGULAMALI USTALIK
## sayaci (ornegin "12 kez su arit"). Boylece seviye kasmak tek basina
## yetmez; oyuncu o dalin isini yaparak ilerler.
##
## Dugum turleri:
##   effects  -> SkillProfile.bonus(etki) uzerinden sistemlere
##   behavior -> yeni eylem/erisim; sistemler `has_behavior(kimlik)` sorar
##   unlock   -> tarif semasi (crafting.known_recipes)
##   power    -> aktif yetenek rutbesi (+N)
## UI'daki aciklama veriden gelir; kodda karsiligi olmayan behavior icerik
## dogrulamasinda HATA sayilir (bkz. KNOWN_BEHAVIORS).

const KNOWN_BEHAVIORS := ["boil_bonus", "filter_saver", "tracking", "rain_bonus", "silent_melee", "lockpick",
	"map_marks", "salvage_plus", "field_repair", "turret_boost", "stabilize", "radio_all", "danger_map",
	"remote_depot", "vehicle_logistics", "green_thumb"]


static func data() -> Dictionary:
	return Content.skill_tree


static func node(id: String) -> Dictionary:
	return data().get("nodes", {}).get(id, {})


static func branch_nodes(branch: String) -> Array:
	var list: Array = []
	var nodes: Dictionary = data().get("nodes", {})
	for id: String in nodes:
		if str(nodes[id].branch) == branch:
			var entry: Dictionary = nodes[id].duplicate()
			entry["id"] = id
			list.append(entry)
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.tier) < int(b.tier) or (int(a.tier) == int(b.tier) and str(a.id) < str(b.id)))
	return list


static func check(id: String, p: Progression) -> Array:
	## [acilabilir_mi, neden]
	var n := node(id)
	if n.is_empty():
		return [false, "Bilinmeyen dugum"]
	if p.nodes.has(id):
		return [false, "Zaten acik"]
	var cost := int(n.get("cost", 1))
	if p.points < cost:
		return [false, "%d puan gerekli (%d var)" % [cost, p.points]]
	if p.level < int(n.get("level", 1)):
		return [false, "Seviye %d gerekli" % int(n.level)]
	for req: String in n.get("requires", []):
		if not p.nodes.has(req):
			return [false, "Once: %s" % str(node(req).get("name", req))]
	var mastery: Dictionary = n.get("mastery", {})
	if not mastery.is_empty():
		var have := int(p.counters.get(str(mastery.counter), 0))
		if have < int(mastery.value):
			return [false, "Ustalik: %s %d/%d" % [counter_label(str(mastery.counter)), have, int(mastery.value)]]
	return [true, ""]


static func counter_label(counter: String) -> String:
	return {"water_purified": "su aritma", "meals_cooked": "yemek pisirme", "kills_firearm": "atesli silahla oldurme",
		"kills_melee": "yakin dovusle oldurme", "containers_searched": "dolap arama", "crafted": "uretim",
		"healed": "tedavi", "colonists": "kurtarilan kisi"}.get(counter, counter)


static func effects_of(nodes_owned: Dictionary) -> Dictionary:
	var total := {}
	for id: String in nodes_owned:
		for effect: String in node(id).get("effects", {}):
			total[effect] = float(total.get(effect, 0.0)) + float(node(id).effects[effect])
	return total


static func behaviors_of(nodes_owned: Dictionary) -> Dictionary:
	var result := {}
	for id: String in nodes_owned:
		var b := str(node(id).get("behavior", ""))
		if b != "":
			result[b] = true
	return result


static func power_bonus(nodes_owned: Dictionary, power_id: String) -> int:
	var bonus := 0
	for id: String in nodes_owned:
		var power: Dictionary = node(id).get("power", {})
		if str(power.get("id", "")) == power_id:
			bonus += int(power.get("ranks", 0))
	return bonus


static func total_cost() -> int:
	var total := 0
	for id: String in data().get("nodes", {}):
		total += int(data().nodes[id].get("cost", 1))
	return total


static func validate(errors: Array) -> void:
	var nodes: Dictionary = data().get("nodes", {})
	var branches := {}
	for b: Dictionary in data().get("branches", []):
		branches[b.id] = 0
	for id: String in nodes:
		var n: Dictionary = nodes[id]
		if not branches.has(str(n.get("branch", ""))):
			errors.append("skill_tree: '%s' bilinmeyen dal" % id)
			continue
		branches[n.branch] += 1
		for req: String in n.get("requires", []):
			if not nodes.has(req):
				errors.append("skill_tree: '%s' bilinmeyen onkosul '%s'" % [id, req])
		var b := str(n.get("behavior", ""))
		if b != "" and not b in KNOWN_BEHAVIORS:
			errors.append("skill_tree: '%s' davranisi kodda yok: %s" % [id, b])
		for recipe_id: Variant in n.get("unlock", []):
			if not Content.recipes.has(str(recipe_id)):
				errors.append("skill_tree: '%s' bilinmeyen tarif '%s'" % [id, recipe_id])
		var power: Dictionary = n.get("power", {})
		if not power.is_empty() and not Content.powers.has(str(power.get("id", ""))):
			errors.append("skill_tree: '%s' bilinmeyen yetenek '%s'" % [id, power.get("id")])
		if not n.has("effects") and b == "" and not n.has("unlock") and power.is_empty():
			errors.append("skill_tree: '%s' hicbir etkisi yok" % id)
	for branch: String in branches:
		if int(branches[branch]) < 8:
			errors.append("skill_tree: '%s' dalinda %d dugum (en az 8)" % [branch, branches[branch]])
