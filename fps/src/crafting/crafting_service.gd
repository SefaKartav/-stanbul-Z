class_name CraftingService
extends RefCounted
## Crafting servisi: yapabilir miyim, yap, sok.
##
## Kalite formulu (oyunun ekonomik omurgasi):
##     cikti = girdi_agirlikli_ortalamasi + istasyon_bonusu (seviye x 6)
##           + tarif_bonusu + beceri_bonusu + sans (-6..+6)
## Girdi ortalamasi AGIRLIKLIDIR: 4 hurda + 1 usta parca usta urun vermez.
##
## FPS surumundeki tek davranis farki TEK ISLEM GUVENLIGIDIR: Python
## surumu girdileri harcadiktan sonra urunu ekliyordu; canta doluysa urun
## sessizce kayboluyordu. Burada butun islem once KOPYA envanterde denenir
## ve ancak basariliysa asil envantere tek adimda uygulanir. Urun sigmiyorsa
## hicbir sey harcanmaz. (Python: game/crafting/service.py)

const STATION_QUALITY_BONUS := 6.0
const SKILL_QUALITY_BONUS := 0.35
const LUCK_RANGE := 6.0
const DISASSEMBLE_RETURN := 0.55
const DISASSEMBLE_QUALITY_LOSS := 12.0

var items: Dictionary
var rng := RandomNumberGenerator.new()
# Bulunmus semalar (tarif kimligi -> true). Oyuncu ve koloni AYNI sozlugu
# paylasir: sema bir kez bulununca zanaatkar da o tarifi uretebilir.
var known_recipes: Dictionary = {}


func _init(p_items: Dictionary, seed_value: int = 20240904) -> void:
	items = p_items
	rng.seed = seed_value


# --- kontrol ---
func check(inventory: Inventory, recipe: RecipeDef, station: String = "hands",
		station_tier: int = 1, skill: float = 0.0) -> Dictionary:
	## {ok, reason, missing: [{ingredient, have, need}], predicted_quality}
	var result := {"ok": false, "reason": "", "missing": [], "predicted_quality": 0.0,
		"recipe": recipe}
	if not recipe.unlocked and not known_recipes.has(recipe.id):
		result.reason = recipe.learn_text() if recipe.learn != "" else "Şema gerekli"
		result["locked"] = true
		return result
	if recipe.station != station and recipe.station != "hands":
		result.reason = "'%s' istasyonu gerekli" % RecipeDef.STATION_NAMES.get(recipe.station, recipe.station)
		return result
	if recipe.station_tier > station_tier and recipe.station != "hands":
		result.reason = "Istasyon seviye %d olmali" % recipe.station_tier
		return result
	# REZERVASYONLU denetim: ayni yigin iki girdiye birden sayilmaz (eskiden
	# 5 civi hem "3 baglanti parcasi" hem "3 civi" girdisini karsiliyor gibi
	# gorunur, uretim eksik harcamayla basarili olurdu). Sira harcamayla ayni.
	var reserved := {}
	for ingredient: Dictionary in _ordered(recipe.inputs):
		var have := 0
		for stack: ItemStack in _sources(inventory, ingredient):
			if have >= ingredient.count:
				break
			var take := mini(ingredient.count - have, stack.quantity - int(reserved.get(stack, 0)))
			if take <= 0:
				continue
			reserved[stack] = int(reserved.get(stack, 0)) + take
			have += take
		if have < ingredient.count:
			result.missing.append({"ingredient": ingredient, "have": have, "need": ingredient.count})
	result.ok = result.missing.is_empty()
	if result.ok:
		result.predicted_quality = _predict_quality(inventory, recipe, station_tier, skill)
	else:
		result.reason = "Malzeme eksik: " + missing_summary(result.missing)
	return result


static func missing_summary(missing: Array) -> String:
	var parts := PackedStringArray()
	for entry: Dictionary in missing:
		var shortfall: int = entry.need - entry.have
		if shortfall > 0:
			parts.append("%dx %s" % [shortfall, RecipeDef.ingredient_key(entry.ingredient)])
	return ", ".join(parts)


static func _ordered(inputs: Array) -> Array:
	## Belirli esya girdileri ONCE, tag girdileri SONRA: "3 civi + 3 herhangi
	## baglanti parcasi" tarifinde vidalar tag'e kalir, civiler esya girdisine.
	var specific := inputs.filter(func(i: Dictionary) -> bool: return i.tag == "")
	var tagged := inputs.filter(func(i: Dictionary) -> bool: return i.tag != "")
	return specific + tagged


func available(inventory: Inventory, ingredient: Dictionary) -> int:
	if ingredient.tag != "":
		return inventory.count_by_tag(ingredient.tag, ingredient.min_quality)
	return inventory.count(ingredient.item, ingredient.min_quality)


func _sources(inventory: Inventory, ingredient: Dictionary) -> Array:
	## Girdiyi karsilayan yiginlar, DUSUK KALITEDEN once.
	if ingredient.tag != "":
		return inventory.matching_tag(ingredient.tag, ingredient.min_quality)
	var result := inventory.stacks.filter(func(s: ItemStack) -> bool:
		return s.definition.id == ingredient.item and s.quality >= ingredient.min_quality \
			and s.quantity > 0)
	result.sort_custom(Inventory._by_quality)
	return result


# --- kalite ---
func _predict_quality(inventory: Inventory, recipe: RecipeDef, station_tier: int, skill: float) -> float:
	var total_quality := 0.0
	var total_count := 0
	# Tahmin, gercek harcamayla AYNI sirayi izlemeli: iki girdi ayni yigini
	# istiyorsa ikinci girdi ilkinin biraktigindan alir.
	var reserved := {}
	for ingredient: Dictionary in _ordered(recipe.consumed_inputs()):
		var remaining: int = ingredient.count
		for stack: ItemStack in _sources(inventory, ingredient):
			if remaining <= 0:
				break
			var free: int = stack.quantity - int(reserved.get(stack, 0))
			var take := mini(remaining, free)
			if take <= 0:
				continue
			reserved[stack] = int(reserved.get(stack, 0)) + take
			total_quality += stack.effective_quality() * take
			total_count += take
			remaining -= take
	var base := (total_quality / total_count) if total_count > 0 else 50.0
	return clampf(base + station_tier * STATION_QUALITY_BONUS + recipe.quality_bonus
		+ skill * SKILL_QUALITY_BONUS, 0.0, 100.0)


func max_craftable(inventory: Inventory, recipe: RecipeDef, station: String = "hands",
		station_tier: int = 1, cap: int = 99) -> int:
	## Kac adet uretilebilir? KOPYA envanterde gercek harcama sirasiyla
	## (dusuk kaliteden) tek tek denenir: iki alternatif girdi ayni yigini
	## iki kez sayamaz; cikti ve yan urun icin yer de hesaba katilir.
	var trial := inventory.clone()
	var count := 0
	var output_def: ItemDef = items.get(recipe.output_id)
	while count < cap:
		if not check(trial, recipe, station, station_tier).ok:
			break
		_consume(trial, recipe)
		if output_def != null and trial.add(ItemStack.new(output_def, recipe.output_count, 50.0)) > 0:
			break
		var fits := true
		for entry: Array in recipe.byproducts:
			var definition: ItemDef = items.get(entry[0])
			if definition != null and trial.add(ItemStack.new(definition, int(entry[1]), 30.0)) > 0:
				fits = false
		if not fits:
			break
		count += 1
	return count


func consumption_plan(inventory: Inventory, recipe: RecipeDef) -> Array:
	## Bir adet icin HANGI yiginlarin harcanacagi (gercek harcamayla ayni
	## sira). Donus: [{ingredient, stacks: [ItemStack kopya]}]. Takim
	## (tuketilmeyen) girdiler listelenmez.
	var trial := inventory.clone()
	var plan: Array = []
	for ingredient: Dictionary in _ordered(recipe.consumed_inputs()):
		var remaining: int = ingredient.count
		var used: Array = []
		for stack: ItemStack in _sources(trial, ingredient):
			if remaining <= 0:
				break
			var take := mini(remaining, stack.quantity)
			used.append(stack.copy(take))
			stack.quantity -= take
			remaining -= take
		plan.append({"ingredient": ingredient, "stacks": used})
	return plan


# --- uretim ---
func craft(inventory: Inventory, recipe: RecipeDef, station: String = "hands",
		station_tier: int = 1, skill: float = 0.0) -> Dictionary:
	## {success, output: ItemStack, byproducts: [], consumed: [], reason}
	var result := {"success": false, "output": null, "byproducts": [], "consumed": [], "reason": ""}
	var checked := check(inventory, recipe, station, station_tier, skill)
	if not checked.ok:
		result.reason = checked.reason
		return result
	var output_def: ItemDef = items.get(recipe.output_id)
	if output_def == null:
		result.reason = "Bilinmeyen cikti: " + recipe.output_id
		return result

	# Once KOPYADA dene: harca, urunu ekle; sigmazsa asil envantere dokunma.
	var trial := inventory.clone()
	var consumed := _consume(trial, recipe)
	var quality := clampf(checked.predicted_quality + rng.randf_range(-LUCK_RANGE, LUCK_RANGE), 0.0, 100.0)

	# Basarisizlik malzemeyi YER ama urun vermez: riskli tarif gercek bir karar.
	if recipe.failure_chance > 0.0 and rng.randf() < recipe.failure_chance:
		inventory.replace_with(trial)
		result.consumed = consumed
		result.reason = "Uretim basarisiz oldu"
		return result

	var output := ItemStack.new(output_def, recipe.output_count, quality)
	var byproducts: Array = []
	for entry: Array in recipe.byproducts:
		var definition: ItemDef = items.get(entry[0])
		if definition != null:
			byproducts.append(ItemStack.new(definition, int(entry[1]), maxf(0.0, quality - 20.0)))

	if trial.add(output.copy()) > 0:
		result.reason = "Canta/depo dolu -- once yer ac"
		return result
	for stack: ItemStack in byproducts:
		# Yan urun sigmazsa urun yine verilir ama yan urun kaybolmaz:
		# islem iptal edilir ve oyuncuya yer acmasi soylenir.
		if trial.add(stack.copy()) > 0:
			result.reason = "Yan urun icin yer yok -- once yer ac"
			return result

	inventory.replace_with(trial)
	result.success = true
	result.output = output
	result.byproducts = byproducts
	result.consumed = consumed
	return result


func _consume(inventory: Inventory, recipe: RecipeDef) -> Array:
	var consumed: Array = []
	for ingredient: Dictionary in _ordered(recipe.consumed_inputs()):
		var remaining: int = ingredient.count
		for stack: ItemStack in _sources(inventory, ingredient):
			if remaining <= 0:
				break
			var take := mini(remaining, stack.quantity)
			consumed.append(stack.copy(take))
			stack.quantity -= take
			remaining -= take
	inventory.compact()
	return consumed


# --- sokme ---
func disassemble(inventory: Inventory, stack: ItemStack, recipes: Dictionary,
		produced_by: Dictionary, return_ratio: float = DISASSEMBLE_RETURN) -> Dictionary:
	## Esyayi girdilerine cevirir. Geri donus %55 ve kalite dususlu: sokmek
	## her zaman kayiptir; "uret-sok" dongusuyle sonsuz malzeme uretilemez.
	var result := {"success": false, "returned": [], "reason": ""}
	var producers: Array = produced_by.get(stack.definition.id, [])
	if producers.is_empty():
		result.reason = "Bu esya sokulemez"
		return result
	var recipe: RecipeDef = recipes[producers[0]]
	var returned: Array = []
	for ingredient: Dictionary in recipe.consumed_inputs():
		var definition: ItemDef = null
		if ingredient.tag != "":
			# Tag girdisi geri verilirken EN UCUZ karsilayan esya secilir;
			# aksi halde sokme bir kalite kazanci makinesi olurdu.
			var options: Array = []
			for candidate: ItemDef in items.values():
				if candidate.has_tag(ingredient.tag):
					options.append(candidate)
			if options.is_empty():
				continue
			options.sort_custom(func(a: ItemDef, b: ItemDef) -> bool:
				return a.tier < b.tier or (a.tier == b.tier and a.value < b.value))
			definition = options[0]
		else:
			definition = items.get(ingredient.item)
			if definition == null:
				continue
		var amount := int(ingredient.count * return_ratio)
		if amount <= 0:
			continue
		returned.append(ItemStack.new(definition, amount, maxf(0.0, stack.quality - DISASSEMBLE_QUALITY_LOSS)))
	if returned.is_empty():
		result.reason = "Geri kazanilabilir parca yok"
		return result

	var trial := inventory.clone()
	var index := inventory.stacks.find(stack)
	if index < 0:
		result.reason = "Esya envanterde degil"
		return result
	var trial_stack: ItemStack = trial.stacks[index]
	trial_stack.quantity -= 1
	trial.compact()
	for piece: ItemStack in returned:
		if trial.add(piece.copy()) > 0:
			result.reason = "Parcalar icin yer yok"
			return result
	inventory.replace_with(trial)
	result.success = true
	result.returned = returned
	return result
