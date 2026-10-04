class_name BuildingClass
extends RefCounted
## Bina sinifi: bir binanin ICINDE NE OLDUGUNU belirleyen tanim.
##
## OSM her binayi zaten etiketliyor (amenity=pharmacy, shop=hardware...);
## bu etiketleri loot tablolarina baglamak elle icerik uretmeden binlari
## ANLAMLI kilar. Eczane, atolye, market ve karakol ayni kutu degildir.
## (Python: game/world/building_class.py)

const FIELDS := ["label", "tables", "search_seconds", "max_searches", "noise_radius", "color", "osm_tags"]
const FALLBACK := "residential"

var id: String
var label: String
var tables: Array = []            # [[loot_tablosu, agirlik], ...]
var search_seconds: float = 4.0
var max_searches: int = 2
var noise_radius: float = 200.0   # eski piksel
var color: Color
var osm_tags: PackedStringArray


func table_ids() -> Array:
	return tables.map(func(entry: Array) -> String: return entry[0])


func pick_table(rng: RandomNumberGenerator) -> String:
	## Agirlikli secim: bir apartmanin bazen mutfak bazen gardirop vermesi.
	var total := 0.0
	for entry: Array in tables:
		total += entry[1]
	var roll := rng.randf_range(0.0, total)
	for entry: Array in tables:
		roll -= entry[1]
		if roll <= 0.0:
			return entry[0]
	return tables[-1][0]


func noise_radius_m() -> float:
	return Units.perception_m(noise_radius)


static func from_dict(source: String, class_id: String, data: Dictionary, errors: Array) -> BuildingClass:
	var v := ContentValidator.new(source, class_id, data, errors)
	v.reject_unknown(FIELDS)
	var b := BuildingClass.new()
	b.id = class_id
	b.label = v.text("label")
	var raw_tables: Variant = data.get("tables")
	if typeof(raw_tables) != TYPE_ARRAY or raw_tables.is_empty():
		v.fail("tables bos olmayan liste olmali")
	else:
		for entry: Variant in raw_tables:
			if typeof(entry) != TYPE_ARRAY or entry.size() != 2 or typeof(entry[0]) != TYPE_STRING \
					or not (typeof(entry[1]) in [TYPE_INT, TYPE_FLOAT]) or float(entry[1]) <= 0.0:
				v.fail('tables girdisi ["tablo_id", pozitif_agirlik] olmali')
				continue
			b.tables.append([entry[0], float(entry[1])])
	b.search_seconds = v.num("search_seconds", 4.0, 0.5, 60.0)
	b.max_searches = v.integer("max_searches", 2, 1)
	b.noise_radius = v.num("noise_radius", 200.0, 0.0)
	b.color = v.color("color", [110, 106, 100])
	b.osm_tags = v.text_list("osm_tags")
	return b
