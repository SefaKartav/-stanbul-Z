class_name CraftingGraph
extends RefCounted
## Crafting grafigi: bagimlilik agaci, ulasilabilirlik, DOGRULAMA.
##
## Yuzlerce esya ve tarifte insan gozu su hatalari GORMEZ: dusmeyen ve
## uretilmeyen esya (olu icerik), kendi kendini gerektiren zincir, hicbir
## tarifin kullanmadigi malzeme. `validate()` aciliste calisir; hata varsa
## oyun acilmaz. (Python: game/crafting/graph.py)

var items: Dictionary
var recipes: Dictionary
var world_drops: Dictionary = {}     # dunyada dogrudan bulunabilen esyalar
var by_tag: Dictionary = {}          # tag -> {item_id: true}
var produced_by: Dictionary = {}     # item_id -> [recipe_id]
var consumed_by: Dictionary = {}     # item_id -> [recipe_id]


func _init(p_items: Dictionary, p_recipes: Dictionary, p_world_drops: Array) -> void:
	items = p_items
	recipes = p_recipes
	for item_id: String in p_world_drops:
		world_drops[item_id] = true
	_build_index()


func _build_index() -> void:
	for item: ItemDef in items.values():
		for tag: String in item.tags:
			if not by_tag.has(tag):
				by_tag[tag] = {}
			by_tag[tag][item.id] = true
	for recipe: RecipeDef in recipes.values():
		_append(produced_by, recipe.output_id, recipe.id)
		for entry: Array in recipe.byproducts:
			_append(produced_by, entry[0], recipe.id)
		for ingredient: Dictionary in recipe.inputs:
			if ingredient.tag != "":
				for item_id: String in by_tag.get(ingredient.tag, {}):
					_append(consumed_by, item_id, recipe.id)
			else:
				_append(consumed_by, ingredient.item, recipe.id)


static func _append(target: Dictionary, key: String, value: String) -> void:
	if not target.has(key):
		target[key] = []
	target[key].append(value)


# --- sorgular ---
func items_with_tag(tag: String) -> Array:
	return by_tag.get(tag, {}).keys()


func recipes_producing(item_id: String) -> Array:
	var result: Array = []
	for recipe_id: String in produced_by.get(item_id, []):
		result.append(recipes[recipe_id])
	return result


func recipes_using(item_id: String) -> Array:
	var seen := {}
	var result: Array = []
	for recipe_id: String in consumed_by.get(item_id, []):
		if not seen.has(recipe_id):
			seen[recipe_id] = true
			result.append(recipes[recipe_id])
	return result


# --- ulasilabilirlik ---
func reachable_items() -> Dictionary:
	## Sabit noktaya kadar: dunyada dusenlerle basla, girdileri karsilanan her
	## tarifin ciktisini ekle, degisim durana kadar tekrarla.
	var reachable := world_drops.duplicate()
	var changed := true
	while changed:
		changed = false
		for recipe: RecipeDef in recipes.values():
			if not _inputs_satisfiable(recipe, reachable):
				continue
			if not reachable.has(recipe.output_id):
				reachable[recipe.output_id] = true
				changed = true
			for entry: Array in recipe.byproducts:
				if not reachable.has(entry[0]):
					reachable[entry[0]] = true
					changed = true
	return reachable


func _inputs_satisfiable(recipe: RecipeDef, available: Dictionary) -> bool:
	for ingredient: Dictionary in recipe.inputs:
		if ingredient.tag != "":
			var any := false
			for item_id: String in by_tag.get(ingredient.tag, {}):
				if available.has(item_id):
					any = true
					break
			if not any:
				return false
		elif not available.has(ingredient.item):
			return false
	return true


# --- dogrulama ---
func validate() -> Array:
	## [{severity: "error"|"warning", kind, message}]
	var issues: Array = []
	for recipe: RecipeDef in recipes.values():
		if not items.has(recipe.output_id):
			issues.append(_issue("error", "bilinmeyen-cikti",
				"tarif '%s' var olmayan '%s' uretiyor" % [recipe.id, recipe.output_id]))
		for entry: Array in recipe.byproducts:
			if not items.has(entry[0]):
				issues.append(_issue("error", "bilinmeyen-yan-urun",
					"tarif '%s' var olmayan '%s' uretiyor" % [recipe.id, entry[0]]))
		for ingredient: Dictionary in recipe.inputs:
			if ingredient.tag != "":
				if by_tag.get(ingredient.tag, {}).is_empty():
					issues.append(_issue("error", "bos-tag",
						"tarif '%s' hicbir esyanin tasimadigi '%s' tag'ini istiyor" % [recipe.id, ingredient.tag]))
			elif not items.has(ingredient.item):
				issues.append(_issue("error", "bilinmeyen-girdi",
					"tarif '%s' var olmayan '%s' istiyor" % [recipe.id, ingredient.item]))

	# Ulasilamayan esya: ne dusuyor ne yapilabiliyor. DONGU tek basina hata
	# degildir; yalnizca esyayi ulasilamaz kildiginda raporlanir.
	var reachable := reachable_items()
	var unreachable: Array = []
	for item_id: String in items:
		if not reachable.has(item_id):
			unreachable.append(item_id)
	unreachable.sort()
	for item_id: String in unreachable:
		var definition: ItemDef = items[item_id]
		issues.append(_issue("error", "ulasilamaz-esya",
			"'%s' (%s) ne loot'ta dusuyor ne uretilebiliyor" % [item_id, definition.name]))

	# Oksuz malzeme: uyari seviyesinde (mermi, medkit tuketilir ama girdi olmaz).
	for item_id: String in items:
		var definition: ItemDef = items[item_id]
		if not ["material", "component", "assembly"].has(definition.category):
			continue
		if consumed_by.get(item_id, []).is_empty():
			issues.append(_issue("warning", "oksuz-malzeme",
				"'%s' (%s) hicbir tarifte kullanilmiyor" % [item_id, definition.name]))
	return issues


static func _issue(severity: String, kind: String, message: String) -> Dictionary:
	return {"severity": severity, "kind": kind, "message": message}


func max_depth_of(item_id: String, seen: Dictionary = {}) -> int:
	if seen.has(item_id):
		return 0
	var producers: Array = produced_by.get(item_id, [])
	if producers.is_empty():
		return 0
	var recipe: RecipeDef = recipes[producers[0]]
	var branch := seen.duplicate()
	branch[item_id] = true
	var best := 0
	for ingredient: Dictionary in recipe.inputs:
		var depth := 0
		if ingredient.tag != "":
			for option: String in by_tag.get(ingredient.tag, {}):
				depth = maxi(depth, max_depth_of(option, branch))
		else:
			depth = max_depth_of(ingredient.item, branch)
		best = maxi(best, depth)
	return best + 1


func stats() -> Dictionary:
	var deepest := 0
	for item_id: String in items:
		deepest = maxi(deepest, max_depth_of(item_id))
	return {"esya": items.size(), "tarif": recipes.size(), "tag": by_tag.size(),
		"dunyada_dusen": world_drops.size(), "uretilebilir": produced_by.size(),
		"en_derin_zincir": deepest}
