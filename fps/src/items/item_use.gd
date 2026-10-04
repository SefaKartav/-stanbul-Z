class_name ItemUse
extends RefCounted
## Esyanin ISLEV SINIFI ve o sinifin calisma zamani isleyicisi.
##
## Belgenin kurali: uretilen her cikti su siniflardan birine girmeli VE o
## sinifi gercekten isleyen bir sistem olmali. "Sadece envanterde duran son
## urun" kabul edilmez. Icerik dogrulamasi (Content) her tarif ciktisini
## buradan gecirir; isleyicisi olmayan cikti OYUNU ACTIRMAZ.
##
##   consume   : yenir/icilir/kullanilir          -> ItemUsage.use
##   throw     : firlatilir                        -> Throwables
##   equip     : kusanilir (zirh, kask, maske...)  -> Game.equip_item
##   weapon    : silah (kusanma/ates/doldurma)     -> PlayerCombat
##   ammo      : mermi (cesit secimi)              -> WeaponState
##   mod       : silaha takilir                    -> Game.attach_mod
##   tool      : alet (toplama, onarim, kilit...)  -> Gathering / crafting takimi
##   place     : insa kipinde yerlestirilir        -> Placeables
##   build     : yapi parcasi / yukseltme          -> BuildMode
##   component : ust tarifte girdi                 -> CraftingService
##   repair    : onarim kiti                       -> ItemUsage.repair
##   vehicle   : arac parcasi ya da yakit          -> Vehicles
##   seed      : saksiya/tarlaya ekilir            -> Placeables (planter)
##   quest     : gorev esyasi                      -> QuestSystem

const CLASSES := ["consume", "throw", "equip", "weapon", "ammo", "mod", "tool", "place", "build",
	"component", "repair", "vehicle", "seed", "quest"]
const CLASS_NAMES := {
	"consume": "Tüketilir", "throw": "Fırlatılır", "equip": "Kuşanılır", "weapon": "Silah",
	"ammo": "Mermi", "mod": "Silaha takılır", "tool": "Alet", "place": "Yerleştirilir (B)",
	"build": "Yapı parçası (B)", "component": "Üst üretimde kullanılır", "repair": "Onarır",
	"vehicle": "Araca bağlanır", "seed": "Ekilir", "quest": "Görev eşyası",
}
## Kodda karsiligi olan alet davranislari (esya etiketleri). Bir alet ya
## bir silah tanimi (toplama/yakin dovus) ya da bunlardan biriyle calisir.
const TOOL_TAGS := ["repair_tool", "electronics_tool", "utility", "radio", "binoculars", "compass",
	"harvest_tool", "lockpick_tool", "crafting_tool", "map_tool", "fishing_tool"]
const REPAIR_KEYS := ["repair_weapon", "repair_armor", "repair_vehicle", "repair_tool", "repair_block"]
const CONSUME_KEYS := ["heal", "stamina", "speed_boost", "regen", "fortify", "focus", "xp", "cure_bleed",
	"cure_infection", "cure_burn", "cure_sick", "cure_fracture"]


static func classify(item: ItemDef) -> String:
	if item.use != "":
		return item.use
	if item.has_tag("quest"):
		return "quest"
	match item.category:
		"weapon":
			return "weapon"
		"ammo":
			return "ammo"
		"mod":
			return "mod"
		"building":
			return "build"
		"vehicle_part":
			return "vehicle"
	for key: String in REPAIR_KEYS:
		if item.effects.has(key):
			return "repair"
	if item.has_tag("throwable"):
		return "throw"
	if item.has_tag("seed"):
		return "seed"
	if item.equippable():
		return "equip"
	if placeable_catalog().has(item.id):
		return "place"
	if item.category == "consumable":
		return "consume"
	if item.category == "tool":
		return "tool"
	return "component"


static func placeable_catalog() -> Dictionary:
	return Content.placeables if Content.placeables != null else {}


static func handler_problem(item: ItemDef) -> String:
	## Bos dize = isleyici var. Degilse NEDEN yok (dogrulama mesaji).
	var kind := classify(item)
	match kind:
		"consume":
			var food := Content.nutrition_of(item.id)
			if not food.is_empty():
				return ""
			for key: String in item.effects:
				if key in CONSUME_KEYS:
					return ""
			# Sarf malzemesi (su bidonu, arıtma tableti): ust tarifte harcanir.
			if Content.graph != null and not Content.graph.recipes_using(item.id).is_empty():
				return ""
			return "tuketilir ama ne besin degeri ne kullanim etkisi var"
		"throw":
			for key: String in ["damage", "noise_radius", "light_radius", "smoke_radius", "shock"]:
				if item.effects.has(key):
					return ""
			return "firlatilir ama etkisi yok"
		"equip":
			if not item.equippable():
				return "kusanma yuvasi yok"
			for key: String in ["armor", "capacity", "toxin_resist", "light_range", "stamina_bonus", "noise_bonus"]:
				if item.effects.has(key):
					return ""
			return "kusanilir ama etkisi yok"
		"weapon":
			return "" if Content.weapons.has(item.weapon_id) else "silah tanimi yok: %s" % item.weapon_id
		"ammo":
			return "" if item.ammo_type != "" else "mermi cinsi yok"
		"mod":
			if item.mod_slot == "" or item.mod_stats.is_empty():
				return "mod yuvasi ya da etkisi yok"
			return ""
		"tool":
			if item.weapon_id != "" and Content.weapons.has(item.weapon_id):
				return ""
			for tag: String in TOOL_TAGS:
				if item.has_tag(tag):
					return ""
			if Content.graph != null and not Content.graph.recipes_using(item.id).is_empty():
				return ""        # takim olarak tarifte kullaniliyor (consumed: false)
			return "alet ama hicbir sistem kullanmiyor"
		"place":
			var info: Dictionary = placeable_catalog().get(item.id, {})
			var kind_id := str(info.get("kind", "station"))
			if not kind_id in Placeables.KINDS:
				return "yerlestirilebilir turu kodda yok: %s" % kind_id
			if kind_id == "station" and not str(info.get("station", "")) in RecipeDef.STATIONS:
				return "istasyon kimligi gecersiz: %s" % info.get("station", "")
			return ""
		"build":
			return "" if Content.build_pieces.has(item.build) else "yapi parcasi tanimi yok: %s" % item.build
		"component":
			if Content.graph != null and Content.graph.recipes_using(item.id).is_empty():
				# Kalan son care: blok maliyeti/onarimi, koloni isi, arac yakiti.
				if Content.build_cost_items.has(item.id) or item.has_tag("chemical_fuel") \
						or item.has_tag("power_source") or item.has_tag("water_raw") or item.has_tag("bait") \
						or item.has_tag("fertilizer"):
					return ""
				return "hicbir ust tarifte kullanilmiyor"
			return ""
		"repair":
			return ""
		"vehicle":
			if item.category == "vehicle_part":
				return "" if item.slot in ItemDef.VEHICLE_SLOTS else "arac yuvasi yok"
			return "" if item.has_tag("chemical_fuel") else "arac icin kullanim yok"
		"seed":
			return "" if Content.crops.has(item.id) else "ekin tanimi yok: %s" % item.id
		"quest":
			return ""
	return "bilinmeyen islev sinifi: %s" % kind


static func how_to(item: ItemDef) -> String:
	## Oyuncuya "bunu nasil kullanirim" aciklamasi (uretim ve envanter ekrani).
	match classify(item):
		"consume":
			return "Envanterde (I) seçip Kullan; hızlı ye/iç: N / U."
		"throw":
			return "Fırlatılır: T ile fırlat, Y ile fırlatılacak olanı değiştir."
		"equip":
			return "Envanterde (I) seçip Kuşan: %s yuvasına takılır." % ItemDef.SLOT_NAMES.get(item.slot, item.slot)
		"weapon":
			return "Çantaya girince boş yuvaya (1-4) geçer; R doldurur."
		"ammo":
			return "Uyumlu silahı doldururken kullanılır; envanterde \"Bu mermiyi kullan\" ile seçilir."
		"mod":
			return "Envanterde silahı seçip \"Mod tak\" ile takılır (uyumlu silahlar: %s)." % ", ".join(item.fits)
		"tool":
			if item.weapon_id != "":
				return "Yuvaya alıp vur: uygun malzemeden kaynak toplar."
			return "Çantada taşınır; ilgili iş (onarım, kilit, üretim) sırasında kendiliğinden kullanılır."
		"place":
			return "İnşa kipinde (B) seçip sol tıkla yerleştir; B kipinde \"Sök\" ile geri alınır."
		"build":
			return "İnşa kipinde (B) yapı parçası olarak konur; \"Yükselt\" ve \"Onar\" aynı kipte."
		"component":
			return "Üst tariflerde girdi olarak kullanılır."
		"repair":
			return "Envanterde seçip Onar: hedef eşyayı/aracı/bloğu onarır."
		"vehicle":
			if item.category == "vehicle_part":
				return "Aracın yanında envanterde (I) \"Araca tak\"."
			return "Aracın yanında envanterde \"Araca yakıt doldur\"."
		"seed":
			return "Saksıya/tarlaya bakıp E ile ek; su ve zamanla büyür."
		"quest":
			return "Görev eşyası (J)."
	return ""
