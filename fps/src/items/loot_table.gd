class_name LootTable
extends RefCounted
## Loot tablosu: dunyada ne dusuyor.
##
## Loot tablolari crafting grafiginin BASLANGIC KUMESIDIR. Kalite tabloda
## degil dogus aninda belirlenir: ayni dolaptan cikan iki kablo farkli
## kalitede olabilir. (Python: game/items/loot.py)

const TABLE_FIELDS := ["id", "name", "rolls", "entries"]
const ENTRY_FIELDS := ["item", "weight", "count", "quality"]

var id: String
var name: String
var rolls_min: int = 1
var rolls_max: int = 2
# Her giris: {item, weight, count_min, count_max, quality_min, quality_max}
var entries: Array = []


func total_weight() -> float:
	var total := 0.0
	for entry: Dictionary in entries:
		total += entry.weight
	return total


func item_ids() -> Array:
	var ids: Array = []
	for entry: Dictionary in entries:
		if not ids.has(entry.item):
			ids.append(entry.item)
	return ids


func roll(items: Dictionary, rng: RandomNumberGenerator, luck: float = 0.0) -> Array:
	## Tabloyu cevirir ve dusen yiginlari dondurur. `luck` hem cekilis
	## sayisini hem kalite araligini yukari kaydirir.
	var rolls := rng.randi_range(rolls_min, rolls_max)
	if luck > 0.0 and rng.randf() < minf(0.6, luck):
		rolls += 1
	var result: Array = []
	var total := total_weight()
	if total <= 0.0:
		return result
	for _i in rolls:
		var pick := rng.randf_range(0.0, total)
		for entry: Dictionary in entries:
			pick -= entry.weight
			if pick > 0.0:
				continue
			var definition: ItemDef = items.get(entry.item)
			if definition == null:
				break
			var amount := rng.randi_range(entry.count_min, entry.count_max)
			if amount <= 0:
				break
			var quality := rng.randf_range(entry.quality_min, entry.quality_max)
			quality = minf(100.0, quality + luck * 10.0)
			result.append(ItemStack.new(definition, amount, quality))
			break
	return result


static func from_dict(source: String, table_id: String, data: Dictionary, errors: Array) -> LootTable:
	var v := ContentValidator.new(source, table_id, data, errors)
	v.reject_unknown(TABLE_FIELDS)
	var table := LootTable.new()
	table.id = table_id
	table.name = v.text("name", table_id)
	var rolls: Variant = data.get("rolls", [1, 2])
	if typeof(rolls) != TYPE_ARRAY or rolls.size() != 2:
		v.fail("'rolls' [min, max] olmali")
	else:
		table.rolls_min = int(rolls[0])
		table.rolls_max = int(rolls[1])
	var raw_entries: Variant = data.get("entries")
	if typeof(raw_entries) != TYPE_ARRAY or raw_entries.is_empty():
		v.fail("'entries' bos olmayan liste olmali")
		return table
	for raw: Variant in raw_entries:
		if typeof(raw) != TYPE_DICTIONARY:
			v.fail("her giris sozluk olmali")
			continue
		var ev := ContentValidator.new(source, table_id, raw, errors)
		ev.reject_unknown(ENTRY_FIELDS)
		var amount: Variant = raw.get("count", [1, 1])
		var quality: Variant = raw.get("quality", [25, 70])
		if typeof(amount) != TYPE_ARRAY or amount.size() != 2:
			ev.fail("'%s' count [min, max] olmali" % raw.get("item"))
			continue
		if typeof(quality) != TYPE_ARRAY or quality.size() != 2:
			ev.fail("'%s' quality [min, max] olmali" % raw.get("item"))
			continue
		table.entries.append({
			"item": ev.text("item"),
			"weight": ev.num("weight", 1.0, 0.0),
			"count_min": int(amount[0]), "count_max": int(amount[1]),
			"quality_min": float(quality[0]), "quality_max": float(quality[1]),
		})
	return table
