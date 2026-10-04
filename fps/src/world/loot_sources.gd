class_name LootSources
extends RefCounted
## "Nerede bulunur?" -- GERCEK loot tanimlarindan turetilir (elle yazilmis
## ipucu yok). Kaynaklar: mobilya container'lari (tip -> havuz -> tablo),
## zombi cesedi, silahla kirilan bloklarin kurtarma dususu.
##
## Olasilik garanti gibi yazilmaz: "sik / ara sira / nadir".

static var _items: Dictionary = {}     # esya -> [{label, places, chance}]
static var _built := false


static func _build() -> void:
	if _built:
		return
	_built = true
	var places := _container_places()
	var types: Dictionary = Content.containers.get("types", {})
	for type_id: String in types:
		var def: Dictionary = types[type_id]
		var total := 0.0
		for pool: Array in def.pools:
			total += float(pool[1])
		var chances := {}
		for pool: Array in def.pools:
			var table: LootTable = Content.loot_tables.get(str(pool[0]))
			if table == null:
				continue
			var tw := table.total_weight()
			for entry: Dictionary in table.entries:
				var c: float = float(pool[1]) / maxf(0.01, total) * entry.weight / maxf(0.01, tw)
				chances[entry.item] = float(chances.get(entry.item, 0.0)) + c
		for item_id: String in chances:
			_add(item_id, str(def.get("label", type_id)).to_lower(), places.get(type_id, []), chances[item_id])
	var corpse: LootTable = Content.loot_tables.get("zombie_corpse")
	if corpse != null:
		for entry: Dictionary in corpse.entries:
			_add(entry.item, "zombi cesedi", [], entry.weight / maxf(0.01, corpse.total_weight()) * 0.6)
	for def: Dictionary in Content.blocks.defs.values():
		for s: Variant in def.salvage:
			if typeof(s) == TYPE_DICTIONARY:
				_add(str(s.item), "kirilan %s blogu" % str(def.name).to_lower(), [], float(s.get("chance", 0.1)))
	# Dunya kaynaklari (loot disi): su noktalari, bozulma, gorev nesneleri.
	_add("water_dirty", "cesme / sadirvan / el pompasi (bos siseyle)", [], 1.0)
	_add("water_dirty", "yagmur varili (us)", [], 0.5)
	for entry: Dictionary in Content.nutrition.get("items", {}).values():
		if entry.has("spoils_to"):
			_add(str(entry.spoils_to), "bozulan pisirilmis yemek", [], 0.3)
	# Toplama (alet sinifiyla vurulan DUNYA blogu), hasat, olta, arac sokumu.
	var tool_word := {"wood": "balta", "stone": "kazma", "metal": "levye/anahtar", "soil": "kürek",
		"glass": "cam kesici", "plant": "orak", "vehicle": "anahtar takımı"}
	var harvest_materials: Dictionary = Content.harvest.get("materials", {})
	for material_id: String in harvest_materials:
		var table: Dictionary = harvest_materials[material_id]
		var block_name := material_id
		var bdef: Variant = Content.blocks.defs.get(material_id)
		if bdef != null:
			block_name = str(bdef.name).to_lower()
		for drop: Variant in table.get("drops", []):
			if typeof(drop) == TYPE_DICTIONARY:
				_add(str(drop.item), "%s ile %s" % [tool_word.get(str(table.get("class", "")), "alet"), block_name], [],
					float(drop.get("chance", 0.5)))
	for drop: Variant in Content.harvest.get("vehicle_salvage", []):
		if typeof(drop) == TYPE_DICTIONARY:
			_add(str(drop.item), "hurda araç sökümü", [], float(drop.get("chance", 0.5)))
	for drop: Variant in Content.harvest.get("fishing", []):
		if typeof(drop) == TYPE_DICTIONARY:
			_add(str(drop.item), "olta (kıyı, iskele)", [], float(drop.get("chance", 0.5)))
	for seed_id: String in Content.crops:
		if seed_id.begins_with("_"):
			continue
		var seed_def := Content.item(seed_id)
		_add(str(Content.crops[seed_id].get("yield", "")), "ekim: %s" % (seed_def.name if seed_def != null else seed_id), [], 1.0)
	for q: Dictionary in Content.quests.get("main", []) + Content.quests.get("side", []):
		for obj: Dictionary in q.get("objectives", []):
			if obj.has("item"):
				_add(str(obj.item), "gorev: %s" % q.title, [], 1.0)
			for given: Array in obj.get("gives", []):
				_add(str(given[0]), "gorev: %s" % q.title, [], 0.5)
	for item_id: String in _items:
		_items[item_id].sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.chance > b.chance)


static func _add(item_id: String, label: String, where: Array, chance: float) -> void:
	if not _items.has(item_id):
		_items[item_id] = []
	for entry: Dictionary in _items[item_id]:
		if entry.label == label:
			entry.chance = maxf(entry.chance, chance)
			return
	_items[item_id].append({"label": label, "places": where, "chance": chance})


static func _container_places() -> Dictionary:
	## Container tipi -> hangi mekanlarda durur (yerlesim adlari).
	var by_asset := {}
	for asset: String in Content.interiors.get("furniture", {}):
		var def: Variant = Content.interiors.furniture[asset]
		if typeof(def) == TYPE_DICTIONARY and def.has("container"):
			by_asset[asset] = str(def.container)
	var room_places := {}
	for layout_id: String in Content.interiors.get("layouts", {}):
		var layout: Dictionary = Content.interiors.layouts[layout_id]
		var label := str(layout.get("label", layout_id)).to_lower()
		var rooms: Array = [str(layout.get("entry", ""))]
		for spec: Array in layout.get("rooms", []):
			rooms.append(str(spec[0]))
		if layout.has("single"):
			rooms.append(str(layout.single))
		for room_id: String in rooms:
			if not room_places.has(room_id):
				room_places[room_id] = []
			if not room_places[room_id].has(label):
				room_places[room_id].append(label)
	var result := {}
	for room_id: String in Content.interiors.get("rooms", {}):
		for spec: Dictionary in Content.interiors.rooms[room_id].get("items", []):
			for key: String in ["asset", "alt"]:
				var type_id := str(by_asset.get(str(spec.get(key, "")), ""))
				if type_id == "":
					continue
				if not result.has(type_id):
					result[type_id] = []
				for place: String in room_places.get(room_id, []):
					if not result[type_id].has(place):
						result[type_id].append(place)
	return result


static func sources(item_id: String) -> Array:
	_build()
	return _items.get(item_id, [])


static func frequency(chance: float) -> String:
	if chance >= 0.18:
		return "sik"
	if chance >= 0.06:
		return "ara sira"
	return "nadir"


static func describe(item_id: String, limit: int = 3) -> String:
	## "gardirop (daire) sik, sifonyer (daire) ara sira"
	var parts := PackedStringArray()
	for entry: Dictionary in sources(item_id).slice(0, limit):
		var where := ""
		if not entry.places.is_empty():
			where = " (%s)" % ", ".join(PackedStringArray(entry.places.slice(0, 2)))
		parts.append("%s%s %s" % [entry.label, where, frequency(entry.chance)])
	return ", ".join(parts)


static func describe_tag(tag: String, limit: int = 3) -> String:
	## Tag girdisi: karsilayan esyalardan en iyi kaynaklar.
	_build()
	var best: Array = []
	for item: ItemDef in Content.items.values():
		if not item.has_tag(tag):
			continue
		for entry: Dictionary in sources(item.id):
			best.append({"text": "%s: %s" % [item.name, entry.label], "chance": entry.chance})
	best.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.chance > b.chance)
	var parts := PackedStringArray()
	var seen := {}
	for entry: Dictionary in best:
		if seen.has(entry.text):
			continue
		seen[entry.text] = true
		parts.append("%s (%s)" % [entry.text, frequency(entry.chance)])
		if parts.size() >= limit:
			break
	return ", ".join(parts)
