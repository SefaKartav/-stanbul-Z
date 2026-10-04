class_name BlockMaterials
extends RefCounted
## Blok malzeme tablosu: `index` (0..255) -> ozellikler.
##
## Voxel dunyasi her hucrede TEK BAYT tutar: malzeme indeksi (0 = hava).
## Bu sinif o baytin anlamini verir. Sicak dongulerde (meshleme, isin
## izleme, carpisma) sozluk aramasi yerine Packed diziler kullanilir;
## milyonlarca hucre sorgusunda fark belirgindir.

const AIR := 0
const SHAPE_FULL := 0
const SHAPE_SLAB := 1
const FIELDS := [
	"index", "name", "max_hp", "bullet_damage_multiplier", "penetration_resistance",
	"texture", "shape", "transparent", "fragile", "liquid", "impact_sound_id",
	"color", "salvage", "zombie_breakable", "render", "passable", "climbable", "interior_only",
]

var defs: Dictionary = {}              # malzeme kimligi -> Dictionary
var by_index: Array = []               # indeks -> Dictionary (bos: null)
var ids: PackedStringArray             # indeks -> kimlik

# Hizli erisim dizileri (indeks ile)
var solid := PackedByteArray()         # carpisma ve mermi engeli
var opaque := PackedByteArray()        # komsu yuzu gizler mi
var transparent := PackedByteArray()
var liquid := PackedByteArray()
var shape := PackedByteArray()
var max_hp := PackedFloat32Array()
var damage_mult := PackedFloat32Array()
var penetration := PackedFloat32Array()
var fragile := PackedByteArray()
var zombie_breakable := PackedByteArray()
# GORUNMEZ katı hucre (render: none): mobilya ve kapilarin carpisma hacmi.
# Mesh'e yuz uretmez, komsu yuzleri gizlemez; fizik/mermi/yol bulma icin
# siradan bir katı bloktur. Gorunen yuz GLB modeldir (bkz. InteriorView).
var hidden := PackedByteArray()
# Gecilebilir (katı degil) ama mermiyle vurulabilir; tirmanilabilir (merdiven).
var passable := PackedByteArray()
var climbable := PackedByteArray()
# Yol yuzeyi: mesh'te blok basina ton farki bastirilir (tek parca asfalt gorunumu).
var smooth := PackedByteArray()
# Yalnizca bina icinde gorulen yuzey (ic siva, parke, fayans, basamak):
# uzak chunk'ta meshlenmez (dis gorunus ayni, ilkel sayisi duser).
var inner := PackedByteArray()
var colors := PackedColorArray()
# Doku katmani indeksleri: [ust, yan, alt] -- atlas katmanina bakar.
var tex_top := PackedInt32Array()
var tex_side := PackedInt32Array()
var tex_bottom := PackedInt32Array()
var texture_ids: PackedStringArray     # doku katmani -> doku kimligi


func _init() -> void:
	# Packed diziler DEGER tipidir: bir listede dolasip resize() cagirmak
	# kopyayi buyuturdu. Bu yuzden tek tek.
	solid.resize(256)
	opaque.resize(256)
	transparent.resize(256)
	liquid.resize(256)
	shape.resize(256)
	fragile.resize(256)
	zombie_breakable.resize(256)
	hidden.resize(256)
	passable.resize(256)
	climbable.resize(256)
	smooth.resize(256)
	inner.resize(256)
	max_hp.resize(256)
	damage_mult.resize(256)
	penetration.resize(256)
	tex_top.resize(256)
	tex_side.resize(256)
	tex_bottom.resize(256)
	colors.resize(256)
	ids.resize(256)
	by_index.resize(256)


static func from_dict(source: String, raw: Dictionary, errors: Array) -> BlockMaterials:
	var table := BlockMaterials.new()
	for material_id: String in raw:
		if material_id.begins_with("_"):
			continue
		var data: Variant = raw[material_id]
		if typeof(data) != TYPE_DICTIONARY:
			errors.append("%s: '%s' -> tanim sozluk olmali" % [source, material_id])
			continue
		var v := ContentValidator.new(source, material_id, data, errors)
		v.reject_unknown(FIELDS)
		var index := v.integer("index", null, 1)
		if index < 1 or index > 254:
			v.fail("index 1..254 araliginda olmali")
			continue
		if table.by_index[index] != null:
			v.fail("index %d zaten '%s' malzemesinde" % [index, table.ids[index]])
			continue
		var texture := v.dict("texture")
		var all_tex: String = texture.get("all", "")
		var def := {
			"id": material_id, "index": index, "name": v.text("name"),
			"max_hp": v.num("max_hp", 100.0, 0.0),
			"bullet_damage_multiplier": v.num("bullet_damage_multiplier", 1.0, 0.0),
			"penetration_resistance": v.num("penetration_resistance", 1.0, 0.0),
			"shape": v.choice("shape", ["full", "slab"], "full"),
			"transparent": v.flag("transparent", false),
			"fragile": v.flag("fragile", false),
			"liquid": v.flag("liquid", false),
			"zombie_breakable": v.flag("zombie_breakable", false),
			"render": v.choice("render", ["mesh", "none"], "mesh"),
			"passable": v.flag("passable", false),
			"climbable": v.flag("climbable", false),
			"interior_only": v.flag("interior_only", false),
			"impact_sound_id": v.text("impact_sound_id", "impact_stone"),
			"color": v.color("color", [128, 128, 128]),
			"texture_top": str(texture.get("top", all_tex)),
			"texture_side": str(texture.get("side", all_tex)),
			"texture_bottom": str(texture.get("bottom", all_tex)),
			"salvage": data.get("salvage", []),
		}
		for key: String in ["texture_top", "texture_side", "texture_bottom"]:
			if def[key] == "":
				v.fail("texture.all ya da top/side/bottom verilmeli")
		if not def.liquid and def.max_hp <= 0.0:
			# Belgenin kurali: normal dunya bloklari gerekcesiz olumsuz olmaz.
			v.fail("katı blokların max_hp degeri pozitif olmali")
		table._register(def)
	return table


func _register(def: Dictionary) -> void:
	var i: int = def.index
	defs[def.id] = def
	by_index[i] = def
	ids[i] = def.id
	var is_liquid: bool = def.liquid
	solid[i] = 0 if is_liquid or def.passable else 1
	passable[i] = 1 if def.passable else 0
	climbable[i] = 1 if def.climbable else 0
	inner[i] = 1 if def.interior_only else 0
	smooth[i] = 1 if def.id in ["asphalt", "asphalt_half", "asphalt_line", "sidewalk", "curb_block", "cobble_half", "cobblestone"] else 0
	hidden[i] = 1 if def.render == "none" else 0
	transparent[i] = 1 if def.transparent else 0
	opaque[i] = 1 if (not def.transparent and not is_liquid and def.shape == "full" and hidden[i] == 0) else 0
	liquid[i] = 1 if is_liquid else 0
	shape[i] = SHAPE_SLAB if def.shape == "slab" else SHAPE_FULL
	max_hp[i] = def.max_hp
	damage_mult[i] = def.bullet_damage_multiplier
	penetration[i] = def.penetration_resistance
	fragile[i] = 1 if def.fragile else 0
	zombie_breakable[i] = 1 if def.zombie_breakable else 0
	colors[i] = def.color
	tex_top[i] = _texture_layer(def.texture_top)
	tex_side[i] = _texture_layer(def.texture_side)
	tex_bottom[i] = _texture_layer(def.texture_bottom)


func _texture_layer(texture_id: String) -> int:
	var existing := texture_ids.find(texture_id)
	if existing >= 0:
		return existing
	texture_ids.append(texture_id)
	return texture_ids.size() - 1


func index_of(material_id: String) -> int:
	var def: Dictionary = defs.get(material_id, {})
	return int(def.get("index", 0))


func get_def(index: int) -> Dictionary:
	var def: Variant = by_index[index] if index >= 0 and index < 256 else null
	return def if def != null else {}


func is_solid(index: int) -> bool:
	return index != AIR and solid[index] == 1


func block_height(index: int) -> float:
	## Carpisma yuksekligi: tam blok 1 m, yarim blok (kaldirim) 0.5 m.
	return 0.5 if shape[index] == SHAPE_SLAB else 1.0
