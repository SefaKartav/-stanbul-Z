class_name ItemStack
extends RefCounted
## Calisma zamani esya yigini.
##
## TANIM (ItemDef) paylasilir ve degismez; YIGIN kalite, dayaniklilik ve
## takili modlari tasir. Yalnizca AYNI kalite bandindaki ayni esya
## yiginlanir -- aksi halde "Iyi bakir kablo" ile "Hurda bakir kablo" tek
## yiginda birlesir ve crafting derinligi kaybolurdu.
## (Python: game/items/item_stack.py)

# Kalitesiz ham malzemenin hesaplardaki notr degeri.
const NEUTRAL_QUALITY := 50.0

var definition: ItemDef
var quantity: int = 1
var quality: float = 50.0
var durability: int = -1
var mods: Array = []           # Array[ItemStack] -- silahlara takili modlar
# Silahin SARJORUNDEKI fisek. Silahla birlikte tasinir: birakilan silah
# dolu kalir, yerden alinan silahta bulundugu kadar mermi vardir.
var loaded: int = 0
# Sarjordeki mermi CESIDI (esya kimligi): zirh delici, oyuk uclu, yakici...
# Bos = ayni capin ilk bulunan mermisi. Oyuncu envanterden "Bu mermiyi
# kullan" ile tercih eder; sonraki doldurmada gecilir.
var ammo_id: String = ""
# BOZULMA: dunya saati (TimeOfDay.total_hours) cinsinden son kullanma; -1 yok.
# Dunya zamanina baglidir: kayit/yukleme saati sifirlamaz. Birlesen iki
# yigindan ERKEN bozulan tarih kalir (taze yemek eskisini "tazelemez").
var expires: float = -1.0


func _init(p_definition: ItemDef, p_quantity: int = 1, p_quality: float = 50.0,
		p_durability: int = -1, p_mods: Array = []) -> void:
	definition = p_definition
	quantity = p_quantity
	quality = p_quality
	durability = p_durability
	mods = p_mods.duplicate()
	if not definition.has_quality:
		quality = 0.0
	if durability < 0:
		durability = definition.durability


# --- gorunum ---
func display_name() -> String:
	if not definition.has_quality:
		return definition.name
	return "%s %s" % [ItemDef.quality_name(quality), definition.name]


func color() -> Color:
	if not definition.has_quality:
		return Color8(216, 220, 226)
	return ItemDef.quality_color(quality)


func tier() -> int:
	return ItemDef.quality_tier(quality)


func effective_quality() -> float:
	## Kalite hesaplarinda VE SIRALAMADA kullanilan deger. Kalitesiz ham
	## malzeme notr 50 sayilir; iki yerde de ayni deger kullanilmazsa
	## formulun soyledigiyle envanterin harcadigi celisir.
	return quality if definition.has_quality else NEUTRAL_QUALITY


func total_weight() -> float:
	return definition.weight * quantity


func broken() -> bool:
	return definition.durability > 0 and durability <= 0


# --- yiginlama ---
func stacks_with(other: ItemStack) -> bool:
	if definition.id != other.definition.id:
		return false
	if definition.stack <= 1:
		return false
	if not mods.is_empty() or not other.mods.is_empty():
		return false
	if loaded != other.loaded or ammo_id != other.ammo_id:
		return false
	if (expires < 0.0) != (other.expires < 0.0):
		return false
	if not definition.has_quality:
		return true
	# Ayni kalite BANDI yeter; birebir esitlik envanteri tek-tek yiginlarla doldururdu.
	return tier() == other.tier()


func merge(other: ItemStack) -> int:
	## `other`dan alabildigi kadarini alir; alinan adedi dondurur.
	if not stacks_with(other):
		return 0
	var space := definition.stack - quantity
	var taken := mini(space, other.quantity)
	if taken <= 0:
		return 0
	if definition.has_quality:
		var total := quantity + taken
		quality = (quality * quantity + other.quality * taken) / total
	quantity += taken
	other.quantity -= taken
	if expires >= 0.0 and other.expires >= 0.0:
		expires = minf(expires, other.expires)
	return taken


func split(amount: int) -> ItemStack:
	if amount >= quantity:
		amount = mini(amount, quantity - 1)
	if amount <= 0:
		return null
	quantity -= amount
	var part := ItemStack.new(definition, amount, quality, durability)
	part.expires = expires
	return part


func copy(p_quantity: int = -1) -> ItemStack:
	var mod_copies: Array = []
	for mod: ItemStack in mods:
		mod_copies.append(mod.copy())
	var result := ItemStack.new(definition, quantity if p_quantity < 0 else p_quantity,
		quality, durability, mod_copies)
	result.loaded = loaded
	result.ammo_id = ammo_id
	result.expires = expires
	return result


# --- modlar ---
func stat_multiplier(stat: String) -> float:
	## Modlar CARPAN olarak birikir: susturucu (x0.35) + uzun namlu (x1.2)
	## = x0.42. Toplama olsaydi iki mod birbirini goturebilirdi.
	var total := 1.0
	for mod: ItemStack in mods:
		total *= float(mod.definition.mod_stats.get(stat, 1.0))
	return total


func mod_in_slot(slot: String) -> ItemStack:
	for mod: ItemStack in mods:
		if mod.definition.mod_slot == slot:
			return mod
	return null


# --- kalicilik ---
func to_dict() -> Dictionary:
	var mod_data: Array = []
	for mod: ItemStack in mods:
		mod_data.append(mod.to_dict())
	var data := {"id": definition.id, "n": quantity, "q": snappedf(quality, 0.01),
		"d": durability, "m": mod_data}
	if loaded > 0:
		data["l"] = loaded
	if ammo_id != "":
		data["a"] = ammo_id
	if expires >= 0.0:
		data["x"] = snappedf(expires, 0.01)
	return data


static func from_dict(data: Dictionary, items: Dictionary) -> ItemStack:
	## Bilinmeyen esya null dondurur: kaldirilmis bir esya kaydi acilmaz
	## hale getirmemeli.
	var definition: ItemDef = items.get(str(data.get("id", "")))
	if definition == null:
		return null
	var mod_stacks: Array = []
	for entry: Variant in data.get("m", []):
		if typeof(entry) == TYPE_DICTIONARY:
			var mod := ItemStack.from_dict(entry, items)
			if mod != null:
				mod_stacks.append(mod)
	var stack := ItemStack.new(definition, maxi(1, int(data.get("n", 1))),
		float(data.get("q", 50.0)), int(data.get("d", -1)), mod_stacks)
	stack.loaded = maxi(0, int(data.get("l", 0)))
	stack.ammo_id = str(data.get("a", ""))
	if stack.ammo_id != "" and not items.has(stack.ammo_id):
		stack.ammo_id = ""
	stack.expires = float(data.get("x", -1.0))
	return stack
