extends Node
## Icerik kayit defteri: data/ altindaki TUM tanimlari yukler ve dogrular.
##
## Projenin en onemli kurali burada uygulanir: ICERIK KOD DEGIL VERIDIR.
## Hepsi JSON'dur, acilista yuklenir, semaya gore dogrulanir ve HATA VARSA
## OYUN ACILMAZ (ana menu hatalari listeler). Kayit defteri yuklendikten
## sonra salt-okunurdur; calisma zamani durumu bilesenlerde tutulur.
## (Python: content/registry.py)

const DATA_DIR := "res://data"

var weapons: Dictionary = {}          # id -> WeaponDef
var zombies: Dictionary = {}          # id -> ZombieDef
var items: Dictionary = {}            # id -> ItemDef
var recipes: Dictionary = {}          # id -> RecipeDef
var loot_tables: Dictionary = {}      # id -> LootTable
var powers: Dictionary = {}           # id -> Dictionary
var building_classes: Dictionary = {} # id -> BuildingClass
var skills: SkillSet
var resources: ResourceSet
var colony: Dictionary = {}
var regions: Dictionary = {}
var travel: Dictionary = {}
var interiors: Dictionary = {}        # bina ici yerlesim (world/interiors.json)
var containers: Dictionary = {}       # aranabilir mobilya kurallari (world/containers.json)
var ui_names: Dictionary = {}         # oyuncuya gosterilen Turkce adlar (world/ui_names.json)
var nutrition: Dictionary = {}        # kisisel aclik/susuzluk (world/nutrition.json)
var quests: Dictionary = {}           # gorev omurgasi (quests/quests.json) -- aktif haritaya uyarlanmis
var quests_source: Dictionary = {}    # dosyadaki hali (yeni sabit harita kimlik/adlari)
var skill_tree: Dictionary = {}       # 6 dalli beceri agaci (skills/skill_tree.json)
var blocks: BlockMaterials
var graph: CraftingGraph
# Insa ve yerlestirme (world/build_catalog.json): tek kaynak. BuildRules ve
# Placeables da buradan okur.
var build_blocks: Dictionary = {}     # eski dogrudan maliyetli bloklar (taslak/iskelet)
var build_pieces: Dictionary = {}     # yapi parcasi esyasi -> {material, shape/size, cells}
var build_upgrades: Dictionary = {}   # malzeme -> {to, cost}
var placeables: Dictionary = {}       # esya kimligi -> yerlestirilebilir tanimi
var build_cost_items: Dictionary = {} # blok maliyeti/onariminda gecen esyalar (oksuz sayilmaz)
var crops: Dictionary = {}            # tohum -> ekin tanimi (world/crops.json)
var harvest: Dictionary = {}          # blok malzemesi -> toplama tablosu (world/harvest.json)
var power_info: Dictionary = {}       # elektrik kurallari (world/power.json)
var zones: Dictionary = {}            # sabit harita alan profilleri (world/zones.json)
var place_roles: Dictionary = {}      # gorev yer kimlikleri -> harita basina karsilik (quests/place_roles.json)

var errors: Array = []
var warnings: Array = []
var loaded := false


func _ready() -> void:
	load_all()


func ok() -> bool:
	return loaded and errors.is_empty()


func load_all() -> void:
	errors.clear()
	warnings.clear()
	weapons = _load_category("weapons", WeaponDef.from_dict)
	zombies = _load_category("enemies", ZombieDef.from_dict)
	items = _load_category("items", ItemDef.from_dict)
	recipes = _load_category("recipes", RecipeDef.from_dict)
	loot_tables = _load_category("loot", LootTable.from_dict)
	powers = _load_category("powers", _power_from_dict)

	var raw: Variant = ContentValidator.load_json(DATA_DIR + "/world/building_classes.json", errors)
	building_classes = {}
	if typeof(raw) == TYPE_DICTIONARY:
		for class_id: String in raw:
			building_classes[class_id] = BuildingClass.from_dict(
				"world/building_classes.json", class_id, raw[class_id], errors)
		if not building_classes.has(BuildingClass.FALLBACK):
			errors.append("world/building_classes.json: yedek sinif '%s' tanimli olmali" % BuildingClass.FALLBACK)

	raw = ContentValidator.load_json(DATA_DIR + "/skills/skills.json", errors)
	skills = SkillSet.from_dict("skills/skills.json", raw if typeof(raw) == TYPE_DICTIONARY else {}, errors)
	raw = ContentValidator.load_json(DATA_DIR + "/world/resources.json", errors)
	resources = ResourceSet.from_dict("world/resources.json", raw if typeof(raw) == TYPE_DICTIONARY else {}, errors)
	raw = ContentValidator.load_json(DATA_DIR + "/world/block_materials.json", errors)
	blocks = BlockMaterials.from_dict("world/block_materials.json", raw if typeof(raw) == TYPE_DICTIONARY else {}, errors)
	raw = ContentValidator.load_json(DATA_DIR + "/city/regions.json", errors)
	regions = raw if typeof(raw) == TYPE_DICTIONARY else {}
	raw = ContentValidator.load_json(DATA_DIR + "/world/travel.json", errors)
	travel = raw if typeof(raw) == TYPE_DICTIONARY else {}
	raw = ContentValidator.load_json(DATA_DIR + "/colony/colony.json", errors)
	colony = raw if typeof(raw) == TYPE_DICTIONARY else {}
	_validate_colony()
	raw = ContentValidator.load_json(DATA_DIR + "/world/interiors.json", errors)
	interiors = raw if typeof(raw) == TYPE_DICTIONARY else {}
	raw = ContentValidator.load_json(DATA_DIR + "/world/containers.json", errors)
	containers = raw if typeof(raw) == TYPE_DICTIONARY else {}
	raw = ContentValidator.load_json(DATA_DIR + "/world/ui_names.json", errors)
	ui_names = raw if typeof(raw) == TYPE_DICTIONARY else {}
	raw = ContentValidator.load_json(DATA_DIR + "/world/nutrition.json", errors)
	nutrition = raw if typeof(raw) == TYPE_DICTIONARY else {}
	if FileAccess.file_exists(DATA_DIR + "/quests/quests.json"):
		raw = ContentValidator.load_json(DATA_DIR + "/quests/quests.json", errors)
		quests = raw if typeof(raw) == TYPE_DICTIONARY else {}
		quests_source = quests.duplicate(true)
	if FileAccess.file_exists(DATA_DIR + "/skills/skill_tree.json"):
		raw = ContentValidator.load_json(DATA_DIR + "/skills/skill_tree.json", errors)
		skill_tree = raw if typeof(raw) == TYPE_DICTIONARY else {}
	_load_build_catalog()
	for pair: Array in [["crops", "/world/crops.json"], ["harvest", "/world/harvest.json"], ["power_info", "/world/power.json"],
			["zones", "/world/zones.json"], ["place_roles", "/quests/place_roles.json"]]:
		if FileAccess.file_exists(DATA_DIR + pair[1]):
			raw = ContentValidator.load_json(DATA_DIR + pair[1], errors)
			set(pair[0], raw if typeof(raw) == TYPE_DICTIONARY else {})

	var world_drops: Array = []
	for table: LootTable in loot_tables.values():
		for item_id: String in table.item_ids():
			if not world_drops.has(item_id):
				world_drops.append(item_id)
	# Loot disi DUNYA KAYNAKLARI: su noktalari (kirli su), bozulma (bozuk
	# yemek), gorev nesneleri ve gorev odulleri. Bunlar da gercek edinme
	# yoludur; grafik "ulasilamaz" saymasin.
	var system_sources: Array = ["water_dirty"]
	for entry: Dictionary in nutrition.get("items", {}).values():
		if entry.has("spoils_to"):
			system_sources.append(str(entry.spoils_to))
	for q: Dictionary in quests.get("main", []) + quests.get("side", []):
		for obj: Dictionary in q.get("objectives", []):
			if obj.has("item"):
				system_sources.append(str(obj.item))
			for entry: Array in obj.get("gives", []):
				system_sources.append(str(entry[0]))
		for entry: Array in q.get("rewards", {}).get("items", []):
			system_sources.append(str(entry[0]))
	# Kaynak toplama (balta/kazma/anahtar), ekin hasadi ve arac sokumu da
	# gercek edinme yoludur.
	for material_id: String in harvest.get("materials", {}):
		for drop: Variant in harvest.materials[material_id].get("drops", []):
			if typeof(drop) == TYPE_DICTIONARY:
				system_sources.append(str(drop.get("item", "")))
	for drop: Variant in harvest.get("vehicle_salvage", []) + harvest.get("fishing", []):
		if typeof(drop) == TYPE_DICTIONARY:
			system_sources.append(str(drop.get("item", "")))
	for seed_id: String in crops:
		if seed_id.begins_with("_"):
			continue
		# Urun ancak tohum ekilerek alinir; tohumun KENDISI loot'tan gelmeli.
		system_sources.append(str(crops[seed_id].get("yield", "")))
	for item_id: String in system_sources:
		if item_id != "" and not world_drops.has(item_id):
			world_drops.append(item_id)
	graph = CraftingGraph.new(items, recipes, world_drops)
	loaded = true
	_check_cross_references()
	if errors.is_empty():
		print("Icerik yuklendi: %d silah, %d dusman, %d esya, %d tarif, %d loot tablosu, %d malzeme" % [
			weapons.size(), zombies.size(), items.size(), recipes.size(),
			loot_tables.size(), blocks.defs.size()])
	else:
		push_error("Icerik dogrulama basarisiz (%d hata)" % errors.size())
		for error: String in errors:
			printerr("  - ", error)


func _load_category(folder: String, factory: Callable) -> Dictionary:
	## Klasordeki tum JSON dosyalarini birlestirir. Ayni kimligin iki
	## dosyada olmasi HATADIR -- sessiz ustune yazma en zor bulunan hatadir.
	var result := {}
	var origin := {}
	var path := DATA_DIR + "/" + folder
	var files := DirAccess.get_files_at(path)
	if files.is_empty():
		return result
	var names := Array(files)
	names.sort()
	for file_name: String in names:
		if not file_name.ends_with(".json"):
			continue
		var source := "%s/%s" % [folder, file_name]
		var raw: Variant = ContentValidator.load_json(path + "/" + file_name, errors)
		if raw == null:
			continue
		if typeof(raw) != TYPE_DICTIONARY:
			errors.append("%s: dosyanin koku sozluk olmali (id -> tanim)" % source)
			continue
		for entry_id: String in raw:
			var data: Variant = raw[entry_id]
			if typeof(data) != TYPE_DICTIONARY:
				errors.append("%s: '%s' -> tanim sozluk olmali" % [source, entry_id])
				continue
			if result.has(entry_id):
				errors.append("%s: '%s' zaten %s icinde tanimli" % [source, entry_id, origin[entry_id]])
				continue
			result[entry_id] = factory.call(source, entry_id, data, errors)
			origin[entry_id] = source
	return result


func _load_build_catalog() -> void:
	## world/build_catalog.json: "blocks" (dogrudan maliyetli, eski), "pieces"
	## (uretilmis yapi parcasi esyasi -> blok), "upgrades" (malzeme -> ust
	## kademe), "placeables" (esya -> yerlestirilebilir).
	build_blocks = {}
	build_pieces = {}
	build_upgrades = {}
	placeables = {}
	build_cost_items = {}
	var raw: Variant = ContentValidator.load_json(DATA_DIR + "/world/build_catalog.json", errors)
	if typeof(raw) != TYPE_DICTIONARY:
		return
	build_blocks = raw.get("blocks", {})
	build_pieces = raw.get("pieces", {})
	build_upgrades = raw.get("upgrades", {})
	placeables = raw.get("placeables", {})
	for group: Dictionary in [build_blocks, build_upgrades]:
		for id: String in group:
			for part: String in ["cost", "repair"]:
				for need: Variant in group[id].get(part, []):
					if typeof(need) == TYPE_DICTIONARY and need.has("item"):
						build_cost_items[str(need.item)] = true
	for id: String in blocks_repair_items():
		build_cost_items[id] = true


func blocks_repair_items() -> Array:
	## Blok malzemesi basina onarim maliyeti (pieces'in malzemeleri).
	var result: Array = []
	for material_id: String in build_upgrades:
		for need: Variant in build_upgrades[material_id].get("repair", []):
			if typeof(need) == TYPE_DICTIONARY and need.has("item"):
				result.append(str(need.item))
	return result


func _validate_build_and_uses() -> void:
	## Belgenin kurali: her tarif ciktisinin islev sinifi ve CALISAN bir
	## isleyicisi olmali; yerlestirilebilirlerin turu kodda tanimli olmali.
	for piece_id: String in build_pieces:
		var piece: Dictionary = build_pieces[piece_id]
		if blocks.index_of(str(piece.get("material", ""))) == 0:
			errors.append("build_catalog: parca '%s' bilinmeyen malzeme '%s'" % [piece_id, piece.get("material")])
		for extra: Variant in piece.get("cells", []):
			if typeof(extra) == TYPE_ARRAY and extra.size() >= 4 and blocks.index_of(str(extra[3])) == 0:
				errors.append("build_catalog: parca '%s' bilinmeyen hucre malzemesi '%s'" % [piece_id, extra[3]])
	for material_id: String in build_upgrades:
		var up: Dictionary = build_upgrades[material_id]
		# Bos "to" = son kademe (yukseltilemez; yalniz onarim/sokum tanimi).
		if blocks.index_of(material_id) == 0 or (str(up.get("to", "")) != "" and blocks.index_of(str(up.to)) == 0):
			errors.append("build_catalog: yukseltme '%s' -> '%s' bilinmeyen malzeme" % [material_id, up.get("to")])
		for part: String in ["cost", "repair"]:
			for need: Variant in up.get(part, []):
				if typeof(need) == TYPE_DICTIONARY and need.has("item") and not items.has(str(need.item)):
					errors.append("build_catalog: yukseltme '%s' bilinmeyen esya '%s'" % [material_id, need.item])
	for item_id: String in placeables:
		var info: Dictionary = placeables[item_id]
		if not items.has(item_id):
			errors.append("build_catalog: yerlestirilebilir '%s' esya olarak yok" % item_id)
		if not str(info.get("kind", "station")) in Placeables.KINDS:
			errors.append("build_catalog: '%s' bilinmeyen tur '%s'" % [item_id, info.get("kind")])
		if not AssetLibrary.has(str(info.get("model", ""))):
			errors.append("build_catalog: '%s' modeli manifestte yok '%s'" % [item_id, info.get("model")])
	for seed_id: String in crops:
		if seed_id.begins_with("_"):
			continue
		var crop: Dictionary = crops[seed_id]
		if not items.has(seed_id) or not items.has(str(crop.get("yield", ""))):
			errors.append("crops.json: '%s' tohum ya da urun esyasi yok" % seed_id)
	for material_id: String in harvest.get("materials", {}):
		if blocks.index_of(material_id) == 0:
			errors.append("harvest.json: bilinmeyen malzeme '%s'" % material_id)
		for drop: Variant in harvest.materials[material_id].get("drops", []):
			if typeof(drop) != TYPE_DICTIONARY or not items.has(str(drop.get("item", ""))):
				errors.append("harvest.json: '%s' gecersiz dusus %s" % [material_id, drop])
	for drop: Variant in harvest.get("vehicle_salvage", []) + harvest.get("fishing", []):
		if typeof(drop) != TYPE_DICTIONARY or not items.has(str(drop.get("item", ""))):
			errors.append("harvest.json: arac sokumu/balik gecersiz dusus %s" % [drop])
	for recipe: RecipeDef in recipes.values():
		var output: ItemDef = items.get(recipe.output_id)
		if output != null:
			var problem := ItemUse.handler_problem(output)
			if problem != "":
				errors.append("tarif '%s' -> '%s': islevsiz cikti (%s)" % [recipe.id, recipe.output_id, problem])
		match recipe.learn_kind():
			"skill":
				if not skill_tree.get("nodes", {}).has(recipe.learn_arg()):
					errors.append("tarif '%s': bilinmeyen beceri '%s'" % [recipe.id, recipe.learn_arg()])
			"quest":
				var found := false
				for q: Dictionary in quests.get("main", []) + quests.get("side", []):
					if str(q.id) == recipe.learn_arg():
						found = true
				if not found:
					errors.append("tarif '%s': bilinmeyen gorev '%s'" % [recipe.id, recipe.learn_arg()])
			"level":
				if not recipe.learn_arg().is_valid_int():
					errors.append("tarif '%s': seviye sayi olmali" % recipe.id)


static func _power_from_dict(source: String, power_id: String, data: Dictionary, errs: Array) -> Dictionary:
	var v := ContentValidator.new(source, power_id, data, errs)
	v.reject_unknown([
		"id", "name", "strategy", "cooldown", "cost", "cast_time", "damage",
		"damage_type", "radius", "range", "speed", "duration", "knockback",
		"targets", "statuses", "color", "noise_radius", "shake", "description",
		"tags", "self_status"])
	return {
		"id": power_id, "name": v.text("name"), "strategy": v.text("strategy"),
		"cooldown": v.num("cooldown", null, 0.05), "cost": v.num("cost", 0.0, 0.0),
		"cast_time": v.num("cast_time", 0.0, 0.0), "damage": v.num("damage", 0.0, 0.0),
		"damage_type": v.choice("damage_type", WeaponDef.DAMAGE_TYPES, "physical"),
		"radius": v.num("radius", 0.0, 0.0), "range": v.num("range", 220.0, 0.0),
		"speed": v.num("speed", 0.0, 0.0), "duration": v.num("duration", 0.0, 0.0),
		"knockback": v.num("knockback", 0.0, 0.0), "targets": v.integer("targets", 1, 1),
		"statuses": data.get("statuses", []), "self_status": data.get("self_status", []),
		"color": v.color("color", [200, 200, 255]),
		"noise_radius": v.num("noise_radius", 120.0, 0.0), "shake": v.num("shake", 0.2, 0.0, 1.0),
		"description": v.text("description", ""), "tags": v.text_list("tags"),
	}


func _validate_colony() -> void:
	## Bozuk is tarifleri oyuna girmeden once reddedilir (Python: load_colony).
	if colony.is_empty():
		errors.append("colony/colony.json bos ya da okunamadi")
		return
	var farming: Dictionary = colony.get("farming", {})
	if not items.has(farming.get("seed", "")) or not items.has(farming.get("yield_item", "")):
		errors.append("colony.json: tarla tohumu veya urunu bulunamadi")
	for key: String in ["seed_count", "side_tiles", "water_daily", "growth_days",
			"yield_count", "quality_per_skill", "fields_per_day"]:
		if float(farming.get(key, 0)) <= 0.0:
			errors.append("colony.json: gecersiz tarla ayari: " + key)
	var settings: Dictionary = colony.get("settings", {})
	for key: String in settings:
		if key == "guard_ammo":
			if not items.has(settings[key]):
				errors.append("colony.json: koloni cephanesi bulunamadi: %s" % settings[key])
		elif typeof(settings[key]) not in [TYPE_INT, TYPE_FLOAT] or float(settings[key]) <= 0.0:
			errors.append("colony.json: koloni ayari pozitif sayi olmali: " + key)
	for role_id: String in colony.get("roles", {}):
		var role: Dictionary = colony.roles[role_id]
		if not ["none", "storage", "workshop", "dorm", "infirmary", "kitchen"].has(role.get("building", "")):
			errors.append("colony.json: '%s' rolunun binasi gecersiz" % role_id)
		for category: String in ["inputs", "outputs"]:
			for item_id: String in role.get(category, {}):
				if not items.has(item_id) or int(role[category][item_id]) < 1:
					errors.append("colony.json: gecersiz koloni is girdisi/ciktisi: " + item_id)
	for profile_id: String in colony.get("profiles", {}):
		for value: Variant in colony.profiles[profile_id].get("skills", {}).values():
			if int(value) < 0 or int(value) > 10:
				errors.append("colony.json: NPC becerisi 0-10 araliginda olmali (%s)" % profile_id)


func _validate_interiors() -> void:
	## Ic mekan ve container verisi: yanlis yazilmis bir tablo/asset kimligi
	## binalari sessizce bos birakirdi.
	var types: Dictionary = containers.get("types", {})
	if types.is_empty():
		errors.append("world/containers.json: 'types' bos")
	for type_id: String in types:
		var def: Dictionary = types[type_id]
		for key: String in ["label", "verb", "search_seconds", "share", "pools"]:
			if not def.has(key):
				errors.append("container '%s': '%s' alani eksik" % [type_id, key])
		for pool: Variant in def.get("pools", []):
			if typeof(pool) != TYPE_ARRAY or pool.size() != 2 or not loot_tables.has(str(pool[0])):
				errors.append("container '%s': gecersiz/bilinmeyen havuz %s" % [type_id, pool])
	for class_id: String in containers.get("class_budget", {}):
		if not building_classes.has(class_id):
			errors.append("containers.json class_budget: bilinmeyen bina sinifi '%s'" % class_id)
	var layouts: Dictionary = interiors.get("layouts", {})
	var rooms: Dictionary = interiors.get("rooms", {})
	var furniture: Dictionary = interiors.get("furniture", {})
	for class_id: String in interiors.get("class_layout", {}):
		if not building_classes.has(class_id):
			errors.append("interiors.json: bilinmeyen bina sinifi '%s'" % class_id)
		if not layouts.has(str(interiors.class_layout[class_id])):
			errors.append("interiors.json: '%s' icin bilinmeyen yerlesim '%s'" % [class_id, interiors.class_layout[class_id]])
		elif not containers.get("class_budget", {}).has(class_id):
			errors.append("containers.json: '%s' sinifinin loot butcesi yok" % class_id)
	for layout_id: String in layouts:
		var layout: Dictionary = layouts[layout_id]
		for key: String in ["floor", "wall"]:
			if blocks.index_of(str(layout.get(key, ""))) == 0:
				errors.append("yerlesim '%s': bilinmeyen malzeme %s=%s" % [layout_id, key, layout.get(key)])
		var room_ids: Array = [str(layout.get("entry", ""))]
		for spec: Variant in layout.get("rooms", []):
			room_ids.append(str(spec[0]))
		for room_id: String in room_ids:
			if not rooms.has(room_id):
				errors.append("yerlesim '%s': bilinmeyen oda '%s'" % [layout_id, room_id])
		if not AssetLibrary.has(str(layout.get("door", ""))):
			errors.append("yerlesim '%s': kapi asseti yok '%s'" % [layout_id, layout.get("door")])
	for room_id: String in rooms:
		for spec: Variant in rooms[room_id].get("items", []):
			for key: String in ["asset", "alt"]:
				if spec.has(key) and not AssetLibrary.has(str(spec[key])):
					errors.append("oda '%s': asset manifestte yok '%s'" % [room_id, spec[key]])
	for asset: String in furniture:
		if asset.begins_with("_"):
			continue
		var def: Dictionary = furniture[asset]
		if not AssetLibrary.has(asset):
			errors.append("mobilya '%s': asset manifestte yok" % asset)
		if def.has("container") and not types.has(str(def.container)):
			errors.append("mobilya '%s': bilinmeyen container tipi '%s'" % [asset, def.container])
		if def.has("material") and blocks.index_of(str(def.material)) == 0:
			errors.append("mobilya '%s': bilinmeyen malzeme '%s'" % [asset, def.material])
	# Tarif girdisi olan her tag'in oyuncuya gosterilecek Turkce adi olmali.
	for recipe: RecipeDef in recipes.values():
		for ingredient: Dictionary in recipe.inputs:
			if ingredient.tag != "" and not ui_names.get("tags", {}).has(ingredient.tag):
				errors.append("ui_names.json: '%s' tag'inin Turkce adi yok (tarif %s)" % [ingredient.tag, recipe.id])
		if not ui_names.get("categories", {}).has(recipe.category):
			errors.append("ui_names.json: tarif kategorisi '%s' icin ad yok" % recipe.category)
	for line: String in AssetLibrary.collisions:
		warnings.append("asset: " + line)


func _check_cross_references() -> void:
	## Kategoriler arasi tutarlilik + crafting grafigi. Yuzlerce esyali bir
	## agacta bu kontrol OPSIYONEL DEGILDIR.
	if weapons.is_empty():
		errors.append("hic silah tanimlanmamis (data/weapons/*.json)")
	if zombies.is_empty():
		errors.append("hic dusman tanimlanmamis (data/enemies/*.json)")
	for zombie: ZombieDef in zombies.values():
		if zombie.sprint_speed > 0.0 and zombie.sprint_speed < zombie.speed:
			errors.append("zombi '%s': sprint_speed speed'den kucuk" % zombie.id)

	var ammo_types := {}
	for item: ItemDef in items.values():
		if item.category == "ammo":
			ammo_types[item.ammo_type] = true
	for item: ItemDef in items.values():
		if item.category == "weapon":
			if not weapons.has(item.weapon_id):
				errors.append("esya '%s': bilinmeyen silah tanimi '%s'" % [item.id, item.weapon_id])
			else:
				var weapon: WeaponDef = weapons[item.weapon_id]
				# Yakin dovus silahi cephane kullanmaz; bos ammo_type tanimin kendisidir.
				if weapon.ammo_type != "" and not ammo_types.has(weapon.ammo_type):
					errors.append("silah '%s': '%s' tipinde hicbir mermi esyasi yok" % [weapon.id, weapon.ammo_type])
		if item.category == "ammo" and item.ammo_type == "":
			errors.append("esya '%s': mermi ama ammo_type bos" % item.id)

	for table: LootTable in loot_tables.values():
		for item_id: String in table.item_ids():
			if not items.has(item_id):
				errors.append("loot '%s': bilinmeyen esya '%s'" % [table.id, item_id])

	# Bina sinifi -> loot tablosu: yanlis yazilmis tablo, binalari sessizce BOS birakir.
	for definition: BuildingClass in building_classes.values():
		for table_id: String in definition.table_ids():
			if not loot_tables.has(table_id):
				errors.append("bina sinifi '%s': bilinmeyen loot tablosu '%s'" % [definition.id, table_id])

	var collisions: Array = []
	for skill_id: String in skills.skills:
		if powers.has(skill_id):
			collisions.append(skill_id)
	if not collisions.is_empty():
		errors.append("beceri ve yetenek kimlikleri cakisiyor: %s" % [collisions])
	if skills.skills.is_empty():
		errors.append("hic beceri tanimlanmamis (data/skills/skills.json)")

	for resource: Dictionary in resources.resources.values():
		var any := false
		for item: ItemDef in items.values():
			if item.has_tag(resource.tag):
				any = true
				break
		if not any:
			errors.append("kaynak '%s': '%s' etiketli hicbir esya yok" % [resource.id, resource.tag])

	for region_id: String in regions:
		var region: Dictionary = regions[region_id]
		for zombie_id: String in region.get("zombies", {}):
			if not zombies.has(zombie_id):
				errors.append("bolge '%s': bilinmeyen zombi '%s'" % [region_id, zombie_id])
		for table_id: Variant in region.get("loot_tables", []):
			if not loot_tables.has(table_id):
				errors.append("bolge '%s': bilinmeyen loot tablosu '%s'" % [region_id, table_id])

	_validate_interiors()
	_validate_build_and_uses()
	_validate_nutrition()
	if not skill_tree.is_empty():
		SkillTree.validate(errors)
	_validate_quests()

	# Blok malzemelerinin kurtarma tablolari gercek esyalara bakmali.
	for def: Dictionary in blocks.defs.values():
		for entry: Variant in def.salvage:
			if typeof(entry) != TYPE_DICTIONARY or not items.has(entry.get("item", "")):
				errors.append("blok '%s': salvage girdisi bilinmeyen esya: %s" % [def.id, entry])

	for issue: Dictionary in graph.validate():
		var line := "[%s] %s: %s" % [issue.severity, issue.kind, issue.message]
		if issue.severity == "error":
			errors.append(line)
		else:
			warnings.append(line)


func _validate_nutrition() -> void:
	## Beslenme tablosundaki her esya ve donus kabi gercek olmali; aksi halde
	## "icildi ama sise kayboldu" turu sessiz hata olur.
	if nutrition.is_empty():
		errors.append("world/nutrition.json bos ya da okunamadi")
		return
	for item_id: String in nutrition.get("items", {}):
		var entry: Dictionary = nutrition.items[item_id]
		if not items.has(item_id):
			errors.append("nutrition.json: bilinmeyen esya '%s'" % item_id)
		for key: String in ["returns", "spoils_to"]:
			if entry.has(key) and not items.has(str(entry[key])):
				errors.append("nutrition.json: '%s' %s bilinmeyen esya '%s'" % [item_id, key, entry[key]])
	for item: ItemDef in items.values():
		if (item.has_tag("food") or item.has_tag("water") or item.has_tag("water_raw")) \
				and not nutrition.get("items", {}).has(item.id) and item.id != "water_canister":
			warnings.append("nutrition.json: '%s' yiyecek/su etiketli ama besin degeri yok" % item.id)


func _validate_quests() -> void:
	## Gorev verisi: esya/tarif/asset kimlikleri gercek olmali; ana omurga en
	## az 20 adim, yan gorevler en az 12 (belge kabul olcutu).
	if quests.is_empty():
		return
	var main: Array = quests.get("main", [])
	var side: Array = quests.get("side", [])
	if main.size() < 20:
		errors.append("quests.json: ana omurga %d adim (en az 20)" % main.size())
	if side.size() < 12:
		errors.append("quests.json: %d yan gorev (en az 12)" % side.size())
	var ids := {}
	for q: Dictionary in main + side:
		if ids.has(q.id):
			errors.append("quests.json: '%s' iki kez tanimli" % q.id)
		ids[q.id] = true
	for q: Dictionary in main + side:
		if q.has("requires") and not ids.has(str(q.requires)):
			errors.append("quests.json: '%s' bilinmeyen onkosul '%s'" % [q.id, q.requires])
		for obj: Dictionary in q.get("objectives", []):
			if obj.has("asset") and not AssetLibrary.has(str(obj.asset)):
				errors.append("quests.json: '%s' asset yok '%s'" % [q.id, obj.asset])
			if obj.has("item") and not items.has(str(obj.item)):
				errors.append("quests.json: '%s' esya yok '%s'" % [q.id, obj.item])
			for need: Dictionary in obj.get("needs", []):
				if need.has("item") and not items.has(str(need.item)):
					errors.append("quests.json: '%s' gereken esya yok '%s'" % [q.id, need.item])
			for entry: Array in obj.get("gives", []):
				if not items.has(str(entry[0])):
					errors.append("quests.json: '%s' verilen esya yok '%s'" % [q.id, entry[0]])
			for recipe_id: Variant in obj.get("recipes", []):
				if not recipes.has(str(recipe_id)):
					errors.append("quests.json: '%s' tarif yok '%s'" % [q.id, recipe_id])
			if obj.has("profile") and not colony.get("profiles", {}).has(str(obj.profile)):
				errors.append("quests.json: '%s' profil yok '%s'" % [q.id, obj.profile])
		var rewards: Dictionary = q.get("rewards", {})
		for entry: Array in rewards.get("items", []):
			if not items.has(str(entry[0])):
				errors.append("quests.json: '%s' odul esyasi yok '%s'" % [q.id, entry[0]])
		for recipe_id: Variant in rewards.get("unlock", []):
			if not recipes.has(str(recipe_id)):
				errors.append("quests.json: '%s' odul tarifi yok '%s'" % [q.id, recipe_id])


static func nutrition_of(item_id: String) -> Dictionary:
	return Content.nutrition.get("items", {}).get(item_id, {})


# --- erisim ---
func item(item_id: String) -> ItemDef:
	return items.get(item_id)


func weapon_for_item(item_id: String) -> WeaponDef:
	var definition: ItemDef = items.get(item_id)
	if definition == null or definition.category != "weapon":
		return null
	return weapons.get(definition.weapon_id)


func ammo_item_for(ammo_type: String) -> ItemDef:
	for definition: ItemDef in items.values():
		if definition.category == "ammo" and definition.ammo_type == ammo_type:
			return definition
	return null


func building_class(class_id: String) -> BuildingClass:
	if building_classes.has(class_id):
		return building_classes[class_id]
	return building_classes[BuildingClass.FALLBACK]


func zombie_spawn_table() -> Array:
	var result: Array = []
	for zombie: ZombieDef in zombies.values():
		if zombie.weight > 0.0:
			result.append([zombie, zombie.weight])
	return result
