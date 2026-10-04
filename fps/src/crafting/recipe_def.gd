class_name RecipeDef
extends RefCounted
## Tarif ve malzeme sorgusu.
##
## BU DOSYADAKI EN ONEMLI FIKIR: girdiler sabit esya kimligi degil TAG
## SORGUSU olabilir -- {"tag": "conductive_metal", "count": 2, "min_quality": 40}.
## Yeni bir malzeme eklemek HICBIR tarifi degistirmez; dogru tag yeter.
## Girdiler duz sozluk olarak tutulur:
##   {item, tag, count, min_quality, consumed}
## `consumed = false` olan girdi TAKIMDIR: kontrol edilir ama harcanmaz.
## (Python: game/crafting/recipe.py)

const FIELDS := [
	"id", "name", "output", "count", "inputs", "station", "station_tier",
	"time", "category", "byproducts", "failure_chance", "description",
	"quality_bonus", "unlocked", "family", "subcategory", "learn", "power", "max_batch",
]
const INGREDIENT_FIELDS := ["item", "tag", "count", "min_quality", "consumed"]

## 12 uretim istasyonu (29 Eylul 2026). Eski sekiz kimlik AYNEN korunur
## (kayitlardaki yerlestirilmis tezgahlar ve tarifler degismez); yeni dort
## istasyon eklendi. Kimlik yeniden adlandirilirsa STATION_ALIASES eski
## kimligi yenisine esler (kayit ve veri okurken).
const STATIONS := ["hands", "workbench", "carpentry", "forge", "masonry", "mechanic", "gunsmith",
	"electronics", "chemistry", "cooking", "water", "farming"]
const STATION_ALIASES := {}
const STATION_NAMES := {
	"hands": "El ile",
	"workbench": "Temel tezgâh",
	"carpentry": "Marangoz tezgâhı",
	"forge": "Dövme ve eritme ocağı",
	"masonry": "Taş ve beton tezgâhı",
	"mechanic": "Mekanik atölye",
	"gunsmith": "Silah tezgâhı",
	"electronics": "Elektronik masası",
	"chemistry": "Kimya seti",
	"cooking": "Pişirme ocağı",
	"water": "Su arıtıcı",
	"farming": "Tarım ve işleme tezgâhı",
}
## On uretim ailesi (belgenin tablosu). Eski tariflerde `family` yoksa
## kategoriden turetilir (bkz. family_of_category).
const FAMILIES := ["build", "process", "tools", "weapons", "defense", "power", "food", "health",
	"storage", "vehicle"]
const FAMILY_NAMES := {
	"build": "Yapı ve güçlendirme", "process": "Kaynak işleme ve bileşen", "tools": "Araç gereç ve bakım",
	"weapons": "Silah, mühimmat ve mod", "defense": "Savunma ve tuzak", "power": "Elektrik ve aydınlatma",
	"food": "Su, yemek ve tarım", "health": "Sağlık ve hayatta kalma", "storage": "Depolama ve koloni",
	"vehicle": "Araç ve keşif",
}
const CATEGORY_FAMILY := {
	"mermi": "weapons", "silah": "weapons", "modifikasyon": "weapons", "atilabilir": "weapons",
	"elektrik": "process", "elektronik": "process", "metal": "process", "mekanik": "process",
	"kimya": "process", "kumas": "process", "tibbi": "health", "zirh": "health", "alet": "tools",
	"insaat": "defense", "istasyon": "storage", "hayatta_kalma": "food",
}
## Ogrenme yolu (`learn`): bos = baslangicta bilinir. "schematic" = sema
## bulunmali (eski `unlocked: false`). "skill:<dugum>" = beceri agaci
## dugumu. "level:<n>" = karakter seviyesi. "quest:<gorev>" = gorev odulu.
const LEARN_KINDS := ["schematic", "skill", "level", "quest"]

var id: String
var name: String
var output_id: String
var output_count: int = 1
var inputs: Array = []            # Array[Dictionary]
var station: String = "workbench"
var station_tier: int = 1
var time: float = 2.0             # saniye
var category: String = "misc"
var byproducts: Array = []        # [[esya_id, adet], ...]
var failure_chance: float = 0.0
var description: String = ""
var quality_bonus: float = 0.0
var unlocked: bool = true         # false ise sema bulunmali
var family: String = ""
var subcategory: String = ""
var learn: String = ""            # bos | schematic | skill:<id> | level:<n> | quest:<id>
var power: float = 0.0            # istasyonun calisirken cektigi guc (W); 0 = elektriksiz
var max_batch: int = 99           # tek iste en fazla adet (kuyruk kapasitesi)


static func family_of_category(category: String) -> String:
	return str(CATEGORY_FAMILY.get(category, "process"))


func learn_kind() -> String:
	return learn.get_slice(":", 0) if learn != "" else ""


func learn_arg() -> String:
	return learn.get_slice(":", 1) if learn.contains(":") else ""


func learn_text() -> String:
	## Kilitli tarifin ACILMA YOLU (oyuncuya gorunur).
	match learn_kind():
		"schematic":
			return "Şema gerekli: karakol, askerî tesis, hapishane, okul, elektronikçi ve sanayi dolaplarında aranır"
		"skill":
			var node := SkillTree.node(learn_arg())
			return "Beceri gerekli: %s (K)" % str(node.get("name", learn_arg()))
		"level":
			return "Seviye %s gerekli" % learn_arg()
		"quest":
			return "Görev ödülü: %s" % learn_arg()
	return ""


func consumed_inputs() -> Array:
	return inputs.filter(func(i: Dictionary) -> bool: return i.consumed)


func tools() -> Array:
	return inputs.filter(func(i: Dictionary) -> bool: return not i.consumed)


static func ingredient_key(ingredient: Dictionary) -> String:
	return ingredient.tag if ingredient.tag != "" else ingredient.item


static func describe_ingredient(ingredient: Dictionary, items: Dictionary) -> String:
	var label: String
	if ingredient.tag != "":
		# Ic tag kimligi oyuncuya gosterilmez: Turkce ad (data/world/ui_names.json).
		label = "herhangi bir " + str(Content.ui_names.get("tags", {}).get(ingredient.tag, ingredient.tag))
	else:
		var definition: ItemDef = items.get(ingredient.item)
		label = definition.name if definition != null else ingredient.item
	var text := "%dx %s" % [ingredient.count, label]
	if ingredient.min_quality > 0.0:
		text += " (kalite %d+)" % int(ingredient.min_quality)
	if not ingredient.consumed:
		text += " [takim]"
	return text


static func from_dict(source: String, recipe_id: String, data: Dictionary, errors: Array) -> RecipeDef:
	var v := ContentValidator.new(source, recipe_id, data, errors)
	v.reject_unknown(FIELDS)
	var recipe := RecipeDef.new()
	recipe.id = recipe_id
	var raw_inputs: Variant = data.get("inputs")
	if typeof(raw_inputs) != TYPE_ARRAY or raw_inputs.is_empty():
		v.fail("'inputs' bos olmayan liste olmali")
	else:
		for raw: Variant in raw_inputs:
			if typeof(raw) != TYPE_DICTIONARY:
				v.fail("girdi sozluk olmali")
				continue
			var iv := ContentValidator.new(source, recipe_id, raw, errors)
			iv.reject_unknown(INGREDIENT_FIELDS)
			var item_id := iv.text("item", "")
			var tag := iv.text("tag", "")
			if (item_id != "") == (tag != ""):
				iv.fail("girdi ya 'item' ya 'tag' icermeli (ikisi birden ya da hicbiri olamaz)")
			recipe.inputs.append({
				"item": item_id, "tag": tag,
				"count": iv.integer("count", 1, 1),
				"min_quality": iv.num("min_quality", 0.0, 0.0, 100.0),
				"consumed": iv.flag("consumed", true),
			})
	var raw_byproducts: Variant = data.get("byproducts", {})
	if typeof(raw_byproducts) != TYPE_DICTIONARY:
		v.fail("'byproducts' sozluk olmali")
	else:
		for key: Variant in raw_byproducts:
			recipe.byproducts.append([str(key), int(raw_byproducts[key])])
	recipe.name = v.text("name")
	recipe.output_id = v.text("output")
	recipe.output_count = v.integer("count", 1, 1)
	recipe.station = v.choice("station", STATIONS, "workbench")
	recipe.station_tier = v.integer("station_tier", 1, 1)
	recipe.time = v.num("time", 2.0, 0.0)
	recipe.category = v.text("category", "misc")
	recipe.failure_chance = v.num("failure_chance", 0.0, 0.0, 0.9)
	recipe.description = v.text("description", "")
	recipe.quality_bonus = v.num("quality_bonus", 0.0, -50.0, 50.0)
	recipe.unlocked = v.flag("unlocked", true)
	recipe.family = v.choice("family", FAMILIES, family_of_category(recipe.category)) if data.has("family") \
		else family_of_category(recipe.category)
	recipe.subcategory = v.text("subcategory", "")
	recipe.learn = v.text("learn", "")
	if recipe.learn != "" and not recipe.learn.get_slice(":", 0) in LEARN_KINDS:
		v.fail("'learn' bilinmeyen tur: %s" % recipe.learn)
	# Eski `unlocked: false` = sema; yeni `learn` ile ayni anlam.
	if not recipe.unlocked and recipe.learn == "":
		recipe.learn = "schematic"
	if recipe.learn != "":
		recipe.unlocked = false
	recipe.power = v.num("power", 0.0, 0.0, 5000.0)
	recipe.max_batch = v.integer("max_batch", 99, 1)
	return recipe
