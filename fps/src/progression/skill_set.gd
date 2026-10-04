class_name SkillSet
extends RefCounted
## Beceri agaci: pasif, adlandirilmis degistiriciler.
##
## Uc tasarim karari (Python: game/progression/skills.py):
##   1. Beceri = degistirici; sistemler "search_speed" gibi ADLARI sorar.
##   2. Degistiriciler TOPLANIR, carpilmaz (ongorulebilir denge).
##   3. Rutbe 1 "temel"dir; bonus (rutbe - 1) ile olceklenir.

const MAX_SKILL_RANK := 5
const MIN_MULTIPLIER := 0.25
const FIELDS := ["name", "description", "color", "effects"]

# skill_id -> {id, name, description, color, effects: {etki: rutbe_basina}}
var skills: Dictionary = {}
var by_effect: Dictionary = {}


static func from_dict(source: String, raw: Dictionary, errors: Array) -> SkillSet:
	var result := SkillSet.new()
	for skill_id: String in raw:
		var data: Variant = raw[skill_id]
		if typeof(data) != TYPE_DICTIONARY:
			errors.append("%s: '%s' -> tanim sozluk olmali" % [source, skill_id])
			continue
		var v := ContentValidator.new(source, skill_id, data, errors)
		v.reject_unknown(FIELDS)
		var effects := v.number_dict("effects")
		if effects.is_empty():
			v.fail("effects bos olmayan sozluk olmali")
		for effect: String in effects:
			if absf(effects[effect]) > 0.5:
				v.fail("effects['%s'] rutbe basina -0.5..0.5 araliginda olmali" % effect)
		result.skills[skill_id] = {
			"id": skill_id, "name": v.text("name"),
			"description": v.text("description", ""),
			"color": v.color("color", [200, 200, 200]), "effects": effects,
		}
		for effect: String in effects:
			if not result.by_effect.has(effect):
				result.by_effect[effect] = []
			result.by_effect[effect].append(skill_id)
	return result


func bonus(effect: String, ranks: Dictionary) -> float:
	var total := 0.0
	for skill_id: String in by_effect.get(effect, []):
		var rank := int(ranks.get(skill_id, 1))
		if rank <= 1:
			continue
		total += float(skills[skill_id].effects[effect]) * (rank - 1)
	return total


func multiplier(effect: String, ranks: Dictionary) -> float:
	return maxf(MIN_MULTIPLIER, 1.0 + bonus(effect, ranks))


func ordered() -> Array:
	var ids := skills.keys()
	ids.sort()
	return ids.map(func(skill_id: String) -> Dictionary: return skills[skill_id])
