class_name ResourceSet
extends RefCounted
## Us kaynaklari: yiyecek, su, tip, yakit.
##
## KAYNAKLAR AYRI BIR EKONOMI DEGIL, DEPONUN TURETILMISIDIR: "yiyecek" bir
## sayac degil, `food` etiketli esyalarin toplamidir. Tuketim de gercek
## esyalari eksilterek yapilir; "konserve buldum ama sayac artmadi" hatasi
## yapisal olarak imkansizdir. (Python: game/base/resources.py)

const FIELDS := ["name", "tag", "per_person_day", "per_structure_day", "critical", "color", "shortage"]
const DEFAULT_SUPPLY_BY_TIER := [1.0, 1.0, 2.5, 4.0, 6.0]

# resource_id -> {id, name, tag, per_person_day, per_structure_day, critical, color, shortage}
var resources: Dictionary = {}


static func from_dict(source: String, raw: Dictionary, errors: Array) -> ResourceSet:
	var result := ResourceSet.new()
	for resource_id: String in raw:
		var data: Variant = raw[resource_id]
		if typeof(data) != TYPE_DICTIONARY:
			errors.append("%s: '%s' -> tanim sozluk olmali" % [source, resource_id])
			continue
		var v := ContentValidator.new(source, resource_id, data, errors)
		v.reject_unknown(FIELDS)
		result.resources[resource_id] = {
			"id": resource_id, "name": v.text("name"), "tag": v.text("tag"),
			"per_person_day": v.num("per_person_day", 0.0, 0.0),
			"per_structure_day": v.num("per_structure_day", 0.0, 0.0),
			"critical": v.flag("critical", false),
			"color": v.color("color", [200, 200, 200]),
			"shortage": v.text("shortage", ""),
		}
	return result


func get_resource(resource_id: String) -> Dictionary:
	return resources.get(resource_id, {})


static func supply_value(item: ItemDef) -> float:
	var explicit: float = item.effects.get("supply", 0.0)
	if explicit > 0.0:
		return explicit
	var tier := clampi(item.tier, 0, DEFAULT_SUPPLY_BY_TIER.size() - 1)
	return DEFAULT_SUPPLY_BY_TIER[tier]


func stock(inventory: Inventory, resource: Dictionary) -> float:
	var total := 0.0
	for stack: ItemStack in inventory.stacks:
		if stack.definition.has_tag(resource.tag):
			total += stack.quantity * supply_value(stack.definition)
	return total


func daily_draw(resource: Dictionary, population: int, structures: int) -> float:
	return resource.per_person_day * maxi(0, population) + resource.per_structure_day * maxi(0, structures)


func days_left(inventory: Inventory, resource: Dictionary, population: int, structures: int) -> float:
	var draw := daily_draw(resource, population, structures)
	if draw <= 0.0:
		return INF
	return stock(inventory, resource) / draw


func consume(inventory: Inventory, resource: Dictionary, amount: float) -> Array:
	## Depodan kaynak eksiltir; [tuketilen, yetti_mi] dondurur. DUSUK
	## TIER'DAN once harcanir: iyi erzak kendiliginden korunur.
	if amount <= 0.0:
		return [0.0, true]
	var candidates := inventory.stacks.filter(func(s: ItemStack) -> bool:
		return s.definition.has_tag(resource.tag))
	candidates.sort_custom(func(a: ItemStack, b: ItemStack) -> bool:
		if a.definition.tier != b.definition.tier:
			return a.definition.tier < b.definition.tier
		return supply_value(a.definition) < supply_value(b.definition))
	var consumed := 0.0
	for stack: ItemStack in candidates:
		if consumed >= amount:
			break
		var per_item := supply_value(stack.definition)
		if per_item <= 0.0:
			continue
		var needed := amount - consumed
		var take := mini(stack.quantity, int(ceil(needed / per_item - 1e-9)))
		if take <= 0:
			continue
		stack.quantity -= take
		consumed += take * per_item
	inventory.compact()
	return [consumed, consumed + 1e-6 >= amount]
