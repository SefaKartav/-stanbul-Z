class_name ItemDef
extends RefCounted
## Esya tanimi (degismez veri) ve KALITE kavrami.
##
## Kalite bir carpan degil bir BOYUTTUR: tarifin giris esigi olur
## (min_quality), cikti kalitesini belirler ve ayni esyanin istatistiklerini
## olceklendirir. Tag'ler ise tarif patlamasini onler: "2 x iletken metal"
## isteyen tarifi bakir kablo da hurda kablo demeti de karsilar.
## (Python: game/items/item_def.py -- davranis birebir korunur.)

const FIELDS := [
	"id", "name", "category", "tags", "tier", "stack", "weight", "value",
	"description", "quality", "durability", "effects", "weapon_id", "ammo_type",
	"mod_slot", "mod_stats", "station", "slot", "fits", "build", "use", "subcategory",
]

const CATEGORIES := [
	"material", "component", "assembly", "consumable", "weapon",
	"ammo", "mod", "tool", "station", "building", "vehicle_part",
]
## Kusanma yuvalari. Eski iki yuva (armor, backpack) aynen korunur.
const SLOTS := ["armor", "helmet", "mask", "backpack", "clothing", "lamp"]
const SLOT_NAMES := {"armor": "Gövde zırhı", "helmet": "Kask", "mask": "Maske", "backpack": "Sırt çantası",
	"clothing": "Giysi", "lamp": "Kafa lambası"}
## Arac parcasi yuvalari (bkz. Vehicles.install_part).
const VEHICLE_SLOTS := ["engine", "tires", "armor", "tank", "rack", "bumper", "lights", "muffler"]

# Kalite bantlari: 0-100 degeri bunlara bolunur.
const TIER_SCRAP := 0
const TIER_STANDARD := 20
const TIER_GOOD := 45
const TIER_MASTER := 70
const TIER_PROTOTYPE := 90

const QUALITY_NAMES := {
	TIER_SCRAP: "Hurda", TIER_STANDARD: "Standart", TIER_GOOD: "Iyi",
	TIER_MASTER: "Usta", TIER_PROTOTYPE: "Prototip",
}

const QUALITY_COLORS := {
	TIER_SCRAP: Color8(132, 128, 120), TIER_STANDARD: Color8(216, 220, 226),
	TIER_GOOD: Color8(98, 190, 118), TIER_MASTER: Color8(86, 152, 224),
	TIER_PROTOTYPE: Color8(206, 142, 232),
}

var id: String
var name: String
var category: String
var tags: Dictionary = {}          # kume gibi kullanilir: tag -> true
var tier: int = 1                  # 1 = ham, 5 = nihai teknoloji
var stack: int = 1
var weight: float = 0.1            # kg
var value: float = 1.0
var description: String = ""
var has_quality: bool = true       # ham hurdanin kalitesi olmaz
var durability: int = 0            # 0 = asinmaz
var effects: Dictionary = {}       # consumable/placeable istatistikleri
var weapon_id: String = ""
var ammo_type: String = ""
var mod_slot: String = ""
var mod_stats: Dictionary = {}
var station: String = ""
var slot: String = ""              # kusanma ya da arac parcasi yuvasi
var fits: PackedStringArray = []   # mod: uydugu silah kategorileri ("pistol", "melee"...)
var build: String = ""             # yapi parcasi: build_catalog.json "pieces" kimligi
var use: String = ""               # islev sinifi (bos = ItemUse.classify turetir)
var subcategory: String = ""


static func quality_tier(quality: float) -> int:
	if quality >= TIER_PROTOTYPE:
		return TIER_PROTOTYPE
	if quality >= TIER_MASTER:
		return TIER_MASTER
	if quality >= TIER_GOOD:
		return TIER_GOOD
	if quality >= TIER_STANDARD:
		return TIER_STANDARD
	return TIER_SCRAP


static func quality_name(quality: float) -> String:
	return QUALITY_NAMES[quality_tier(quality)]


static func quality_color(quality: float) -> Color:
	return QUALITY_COLORS[quality_tier(quality)]


func has_tag(tag: String) -> bool:
	return tags.has(tag)


func tag_list() -> PackedStringArray:
	var result := PackedStringArray()
	for tag: String in tags:
		result.append(tag)
	return result


static func from_dict(source: String, item_id: String, data: Dictionary, errors: Array) -> ItemDef:
	var v := ContentValidator.new(source, item_id, data, errors)
	v.reject_unknown(FIELDS)
	var item := ItemDef.new()
	item.id = item_id
	item.name = v.text("name")
	item.category = v.choice("category", CATEGORIES)
	for tag in v.text_list("tags"):
		item.tags[tag] = true
	item.tier = v.integer("tier", 1, 1)
	item.stack = v.integer("stack", 1, 1)
	item.weight = v.num("weight", 0.1, 0.0)
	item.value = v.num("value", 1.0, 0.0)
	item.description = v.text("description", "")
	# Ham hurdanin kalitesi olmaz: bir vida ya vardir ya yoktur.
	item.has_quality = v.flag("quality", item.category != "material")
	item.durability = v.integer("durability", 0, 0)
	item.effects = v.number_dict("effects")
	item.weapon_id = v.text("weapon_id", "")
	item.ammo_type = v.text("ammo_type", "")
	item.mod_slot = v.text("mod_slot", "")
	item.mod_stats = v.number_dict("mod_stats")
	item.station = v.text("station", "")
	item.slot = v.text("slot", "")
	if item.slot == "":
		# Eski esyalar: yuva etkiden turetilir (gaz maskesi artik gercekten kusanilir).
		if item.effects.has("armor"):
			item.slot = "armor"
		elif item.effects.has("capacity"):
			item.slot = "backpack"
		elif item.effects.has("toxin_resist"):
			item.slot = "mask"
	elif item.category == "vehicle_part":
		if not item.slot in VEHICLE_SLOTS:
			v.fail("arac parcasi yuvasi bilinmiyor: %s" % item.slot)
	elif not item.slot in SLOTS:
		v.fail("kusanma yuvasi bilinmiyor: %s" % item.slot)
	item.fits = v.text_list("fits")
	item.build = v.text("build", "")
	item.use = v.text("use", "")
	item.subcategory = v.text("subcategory", "")
	return item


func equippable() -> bool:
	return slot in SLOTS and category != "vehicle_part"
