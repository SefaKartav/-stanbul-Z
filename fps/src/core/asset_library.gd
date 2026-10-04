class_name AssetLibrary
extends RefCounted
## Asset paketi erisimi: SABIT KIMLIK -> model.
##
## Kaynak: res://assets/istanbul_z_v1/manifest.json (kullanicinin paketi).
## Kod asla dosya yolu yazmaz, kimlik ister ("pistol", "zombie_walker").
## Paket guncellendiginde ayni kimlikle yeni dosya gelir; kod degismez.
## Kimlik bulunamazsa manifestteki olcude NOTR bir yer tutucu kutu doner:
## eksik final asset oyunu acilmaz yapmaz.

const PACK_DIR := "res://assets/istanbul_z_v1/"
const ITEM_MODELS := "res://data/world/item_models.json"
## 300 modellik paket: manifest.json eski 94 kaydi AYNEN tasir, yeni 206
## kayit manifest_additions.json'dadir. Iki liste burada birlestirilir;
## eski kimlik ASLA ezilmez (cakisma uyari olur, eski kayit kalir).
## 600 modellik genisleme (25 Eylul 2026): manifest_expansion_600.json YALNIZCA
## 300 yeni iz2_ kaydini tasir. Uc liste ayni anda okunur; birlesik
## manifest_combined_600.json yalnizca katalog/inceleme icindir ve OKUNMAZ
## (ayni kimlikleri ikinci kez yukleyip cakistirirdi).
const MANIFESTS := ["manifest.json", "manifest_additions.json", "manifest_expansion_600.json"]
## Paketin yan sozlesmeleri (motor bunlari kendiliginden okumaz):
##   interaction_metadata.json : marker'lar, parca bazli carpisma onerileri,
##                               hareket eksenleri, montaj yukseklikleri
##   vehicle_compatibility.json: eski dolu arac -> *_shell_open + *_cabin
const METADATA := "interaction_metadata.json"
const METADATA_EXPANSION := "interaction_metadata_expansion.json"
const ICON_DIR := "icons_128/"
const UI_ICON_DIR := "ui_icons/"
const VEHICLE_PAIRS := "vehicle_compatibility.json"
## Ek paketler (29 Eylul 2026): her paket KENDI kokunden okunur; kayit
## yolu o koke goredir. Paket klasoru yoksa sessizce atlanir (paket henuz
## eklenmemis olabilir). Ayni kimlik ikinci kez gelirse ilk kayit korunur.
## `replaces_asset_id` kaynagi SILMEZ: yalnizca gorsel (sahne + ikon)
## yeni kayittan gelir; esya/kayit kimlikleri eski kimlikle kalir.
const EXTRA_PACKS := [
	{"dir": "res://assets/istanbul_z_soft_expansion/", "manifests": ["manifest_soft_expansion.json"],
		"metadata": ["interaction_metadata_soft.json"], "icon_dir": "icons/"},
]

static var _entries: Dictionary = {}
static var _dir_of: Dictionary = {}      # kimlik -> paket koku
static var _overrides: Dictionary = {}   # eski kimlik -> gorseli saglayan yeni kimlik
static var _scenes: Dictionary = {}
static var _requested: Dictionary = {}   # kimlik -> yol (arka planda yukleniyor)
# Kaynak materyal -> hazirlanmis kopya. Eskiden HER ornek kendi kopyasini
# uretiyordu: 300 mobilya = 300+ ayri materyal (toplu cizim yok, kurulum
# pahali). Ayni kaynak artik tek hazir kopyayi paylasir. Ornek basina
# materyal DEGISTIREN kod yoktur; gerekirse duplicate() ile ayrilmali.
static var _prepared: Dictionary = {}
static var _item_rules: Dictionary = {}
static var _metadata: Dictionary = {}
static var _vehicle_pairs: Dictionary = {}
static var collisions: Array = []
static var missing_files: Array = []     # manifestte olup dosyasi olmayan kimlikler
static var source_of: Dictionary = {}    # kimlik -> hangi manifestten
static var _loaded := false


static func _ensure() -> void:
	## Ilk cagri ANA is parcaciginda yapilmali (bkz. CityGenerator._init):
	## isci is parcaciklari yalnizca doldurulmus sozlukleri okur.
	if _loaded:
		return
	_loaded = true
	var errors: Array = []
	for file_name: String in MANIFESTS:
		var manifest: Variant = ContentValidator.load_json(PACK_DIR + file_name, errors)
		if typeof(manifest) != TYPE_DICTIONARY:
			continue
		for entry: Variant in manifest.get("assets", []):
			if typeof(entry) != TYPE_DICTIONARY or not entry.has("id"):
				continue
			if _entries.has(entry.id):
				collisions.append("%s: '%s' zaten tanimli, eski kayit korundu" % [file_name, entry.id])
				continue
			_entries[entry.id] = entry
			_dir_of[entry.id] = PACK_DIR
			source_of[entry.id] = file_name
			if file_name == "manifest_expansion_600.json" and not ResourceLoader.exists(PACK_DIR + str(entry.get("path", ""))) \
					and not FileAccess.file_exists(PACK_DIR + str(entry.get("path", ""))):
				missing_files.append(str(entry.id))
	var meta: Variant = ContentValidator.load_json(PACK_DIR + METADATA, errors)
	if typeof(meta) == TYPE_DICTIONARY:
		_metadata = meta.get("assets", {})
	# Genisleme metadatasi: yeni kimlikler eklenir; eski kimligin kaydi EZILMEZ.
	var meta_x: Variant = ContentValidator.load_json(PACK_DIR + METADATA_EXPANSION, errors)
	if typeof(meta_x) == TYPE_DICTIONARY:
		var extra: Dictionary = meta_x.get("assets", {})
		for id: String in extra:
			if _metadata.has(id):
				collisions.append("%s: metadata '%s' zaten tanimli, eski kayit korundu" % [METADATA_EXPANSION, id])
				continue
			_metadata[id] = extra[id]
	var pairs: Variant = ContentValidator.load_json(PACK_DIR + VEHICLE_PAIRS, errors)
	if typeof(pairs) == TYPE_DICTIONARY:
		for entry: Variant in pairs.get("vehicles", []):
			if typeof(entry) == TYPE_DICTIONARY:
				_vehicle_pairs[str(entry.get("original_id", ""))] = entry
	var rules: Variant = ContentValidator.load_json(ITEM_MODELS, errors)
	if typeof(rules) == TYPE_DICTIONARY:
		_item_rules = rules
	# Ek paketler EN SON: eski paketin metadata'si `_metadata`yi bastan atar;
	# once yuklenirse yeni paketin kayitlari silinirdi.
	for pack: Dictionary in EXTRA_PACKS:
		_load_extra_pack(pack, errors)
	for error: String in errors:
		push_warning(error)
	for line: String in collisions:
		push_warning("Asset kimlik cakismasi: " + line)


static func _load_extra_pack(pack: Dictionary, errors: Array) -> void:
	var dir: String = pack.dir
	if not DirAccess.dir_exists_absolute(dir):
		return
	for file_name: String in pack.manifests:
		if not FileAccess.file_exists(dir + file_name):
			continue
		var manifest: Variant = ContentValidator.load_json(dir + file_name, errors)
		if typeof(manifest) != TYPE_DICTIONARY:
			continue
		for entry: Variant in manifest.get("assets", []):
			if typeof(entry) != TYPE_DICTIONARY or not entry.has("id"):
				continue
			var id := str(entry.id)
			if _entries.has(id):
				collisions.append("%s: '%s' zaten tanimli, eski kayit korundu" % [file_name, id])
				continue
			_entries[id] = entry
			_dir_of[id] = dir
			source_of[id] = file_name
			var path := dir + str(entry.get("path", ""))
			if not ResourceLoader.exists(path) and not FileAccess.file_exists(path):
				missing_files.append(id)
			var replaces: Variant = entry.get("replaces_asset_id")
			if typeof(replaces) == TYPE_STRING and replaces != "":
				_overrides[replaces] = id
	for file_name: String in pack.metadata:
		if not FileAccess.file_exists(dir + file_name):
			continue
		var meta: Variant = ContentValidator.load_json(dir + file_name, errors)
		if typeof(meta) != TYPE_DICTIONARY:
			continue
		var extra: Dictionary = meta.get("assets", {})
		for id: String in extra:
			if _metadata.has(id):
				collisions.append("%s: metadata '%s' zaten tanimli, eski kayit korundu" % [file_name, id])
				continue
			_metadata[id] = _normalize_metadata(extra[id])


static func _normalize_metadata(data: Dictionary) -> Dictionary:
	## Yeni paket hareketleri `part_motion` altinda ve `path` anahtarsiz yazar
	## ({axis, angle} ya da {delta}); pose_open eski bicimi okur.
	if data.has("motions") or not data.has("part_motion"):
		return data
	var motions: Dictionary = {}
	for part: String in data.part_motion:
		var motion: Dictionary = (data.part_motion[part] as Dictionary).duplicate()
		if not motion.has("path"):
			motion["path"] = "translation" if motion.has("delta") else "rotation"
		motions[part] = motion
	var result := data.duplicate()
	result["motions"] = motions
	return result


static func pack_dir(id: String) -> String:
	_ensure()
	return _dir_of.get(id, PACK_DIR)


static func visual_id(id: String) -> String:
	## Gorseli saglayan kimlik: `replaces_asset_id` ile ezilmis ve dosyasi
	## gercekten varsa yeni kayit, yoksa kendisi.
	_ensure()
	var other: String = _overrides.get(id, "")
	if other != "" and not missing_files.has(other):
		return other
	return id


static func count() -> int:
	_ensure()
	return _entries.size()


static func ids() -> Array:
	_ensure()
	return _entries.keys()


static func icon(id: String) -> Texture2D:
	## Model onizlemesinden uretilmis 128 px ikon (envanter/katalog). Yoksa null.
	_ensure()
	var vid := visual_id(id)
	var data: Dictionary = _entries.get(vid, {})
	var candidates: Array = []
	if data.has("icon_path"):
		candidates.append(pack_dir(vid) + str(data.icon_path))
	candidates.append(PACK_DIR + ICON_DIR + vid + ".png")
	if vid != id:
		candidates.append(PACK_DIR + ICON_DIR + id + ".png")
	for path: String in candidates:
		if ResourceLoader.exists(path):
			return load(path)
	return null


static func ui_icon(name: String) -> Texture2D:
	## HUD simgeleri: satiety, hydration, stamina, dirty_water, spoilage, mission.
	var path := PACK_DIR + UI_ICON_DIR + name + ".png"
	if ResourceLoader.exists(path):
		return load(path)
	return null


static func metadata(id: String) -> Dictionary:
	## interaction_metadata.json kaydi (yoksa bos).
	_ensure()
	return _metadata.get(id, {})


static func marker(id: String, marker_name: String) -> Transform3D:
	## GLB icindeki bos (Empty) dugumun yerel donusumu; once sahneye, yoksa
	## metadata'ya bakilir. Bulunamazsa Transform3D() -- cagiran kontrol eder.
	var packed := scene(id)
	if packed != null:
		var state := packed.get_state()
		for i in state.get_node_count():
			if state.get_node_name(i) == marker_name:
				for p in state.get_node_property_count(i):
					if state.get_node_property_name(i, p) == "transform":
						return state.get_node_property_value(i, p)
				for p in state.get_node_property_count(i):
					if state.get_node_property_name(i, p) == "position":
						return Transform3D(Basis(), state.get_node_property_value(i, p))
	var data: Dictionary = metadata(id).get("markers", {}).get(marker_name, {})
	if data.has("translation"):
		var t: Array = data.translation
		var q: Array = data.get("rotation_quaternion", [0, 0, 0, 1])
		return Transform3D(Basis(Quaternion(q[0], q[1], q[2], q[3])), Vector3(t[0], t[1], t[2]))
	return Transform3D()


static func has_marker(id: String, marker_name: String) -> bool:
	return metadata(id).get("markers", {}).has(marker_name) or marker(id, marker_name) != Transform3D()


static func vehicle_pair(original_id: String) -> Dictionary:
	## {shell, cabin}: suruse uygun acik kabuk + kabin; yoksa bos.
	_ensure()
	var pair: Dictionary = _vehicle_pairs.get(original_id, {})
	if pair.is_empty():
		return {}
	var shell := str(pair.get("use_shell", ""))
	var cabin := str(pair.get("use_cabin", ""))
	if not has(shell) or not has(cabin):
		return {}
	return {"shell": shell, "cabin": cabin}


static func pose_open(node: Node3D, id: String, amount: float) -> void:
	## Kapak/kapi/cekmece: metadata'daki hareketi (menteşe ekseni + aci ya da
	## kayma deltasi) `amount` (0 kapali .. 1 acik) oraninda uygular. Animasyon
	## oynaticiya gerek yok; kaydedilen "acik" durumu yuklemede aynen kurulur.
	var motions: Dictionary = metadata(id).get("motions", {})
	for part_name: String in motions:
		var part := node.find_child(part_name, true, false) as Node3D
		if part == null:
			continue
		if not part.has_meta("rest"):
			part.set_meta("rest", part.transform)
		var rest: Transform3D = part.get_meta("rest")
		var motion: Dictionary = motions[part_name]
		if motion.get("path", "") == "rotation":
			var axis: Array = motion.get("axis", [0, 1, 0])
			var angle := float(motion.get("angle", 1.5)) * amount
			part.transform = Transform3D(rest.basis * Basis(Vector3(axis[0], axis[1], axis[2]).normalized(), angle), rest.origin)
		elif motion.get("path", "") == "translation":
			var delta: Array = motion.get("delta", [0, 0, 0])
			part.transform = Transform3D(rest.basis, rest.origin + rest.basis * (Vector3(delta[0], delta[1], delta[2]) * amount))


static func has(id: String) -> bool:
	_ensure()
	return _entries.has(id)


static func entry(id: String) -> Dictionary:
	_ensure()
	return _entries.get(id, {})


static func scene(id: String) -> PackedScene:
	_ensure()
	if _scenes.has(id):
		return _scenes[id]
	var result: PackedScene = null
	var vid := visual_id(id)
	var data: Dictionary = _entries.get(vid, {})
	if _requested.has(id):
		result = ResourceLoader.load_threaded_get(_requested[id])
		_requested.erase(id)
	elif not data.is_empty():
		var path: String = pack_dir(vid) + str(data.path)
		if ResourceLoader.exists(path):
			result = load(path)
	_scenes[id] = result
	return result


static func warm(prefixes: Array) -> int:
	## Verilen klasorlerdeki modelleri ARKA PLANDA yuklemeye baslar. Ic mekan
	## gorselleri kosarken ilk kez gerektiginde GLB'nin diskten ana is
	## parcaciginda yuklenmesi tek binada 28 ms'lik takilma yapiyordu.
	## scene() istenen model hazir degilse o an bekler (davranis ayni kalir).
	_ensure()
	var started := 0
	for id: String in _entries:
		if _scenes.has(id) or _requested.has(id):
			continue
		var vid := visual_id(id)
		var rel := str(_entries[vid].get("path", ""))
		var wanted := false
		for prefix: String in prefixes:
			if rel.begins_with(prefix):
				wanted = true
		var path := pack_dir(vid) + rel
		if not wanted or not ResourceLoader.exists(path):
			continue
		if ResourceLoader.load_threaded_request(path) == OK:
			_requested[id] = path
			started += 1
	return started


static func instantiate(id: String) -> Node3D:
	var packed := scene(id)
	if packed != null:
		var node: Node3D = packed.instantiate()
		_prepare_materials(node)
		return node
	return placeholder(id)


static func placeholder(id: String) -> Node3D:
	var data := entry(id)
	var size := Vector3(0.3, 0.3, 0.3)
	var offset := Vector3(0, 0.15, 0)
	if data.has("bounds_min") and data.has("bounds_max"):
		var bmin := Vector3(data.bounds_min[0], data.bounds_min[1], data.bounds_min[2])
		var bmax := Vector3(data.bounds_max[0], data.bounds_max[1], data.bounds_max[2])
		size = bmax - bmin
		offset = (bmin + bmax) * 0.5
	var root := Node3D.new()
	root.name = id + "_yer_tutucu"
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.55, 0.55, 0.52)
	box.material = material
	mesh.mesh = box
	mesh.position = offset
	root.add_child(mesh)
	return root


static func bounds(id: String) -> AABB:
	var data := entry(id)
	if not data.has("bounds_min"):
		return AABB(Vector3(-0.15, 0, -0.15), Vector3(0.3, 0.3, 0.3))
	var bmin := Vector3(data.bounds_min[0], data.bounds_min[1], data.bounds_min[2])
	var bmax := Vector3(data.bounds_max[0], data.bounds_max[1], data.bounds_max[2])
	return AABB(bmin, bmax - bmin)


static func _prepare_materials(node: Node) -> void:
	## Paketteki renkler VERTEX COLOR'dir; modeli tek renkli bir materyalle
	## degistirmek yasak (paket README'si). Burada yalnizca vertex rengi
	## albedo olarak kullanilsin ve mat kalsin diye ayarlanir.
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			for s in mesh_instance.mesh.get_surface_count():
				var material := mesh_instance.get_active_material(s)
				if material != null and _prepared.has(material):
					var shared: Material = _prepared[material]
					mesh_instance.set_surface_override_material(s, shared)
					if shared.resource_name.begins_with("glass"):
						mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					continue
				if material is StandardMaterial3D and material.resource_name.begins_with("glass"):
					# CAM ISTISNASI: yeni paketin 'glass_clear' materyali saydamdir
					# (alfa 0.09). Vertex rengi zorlanmaz; iki yuzden gorunur,
					# golge dusurmez (ic mekan/kabin kararmasin). Diger modellerin
					# vertex renk ayarina dokunulmaz.
					var glass: StandardMaterial3D = material.duplicate()
					glass.cull_mode = BaseMaterial3D.CULL_DISABLED
					glass.roughness = 0.1
					_prepared[material] = glass
					mesh_instance.set_surface_override_material(s, glass)
					mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					continue
				if material is StandardMaterial3D:
					var copy: StandardMaterial3D = material.duplicate()
					copy.vertex_color_use_as_albedo = true
					# Paketin katalog gorselleri ile karsilastirildiginda renkler
					# sRGB degerleri olarak yazilmis; dogrusal okunursa soluk cikar.
					copy.vertex_color_is_srgb = true
					copy.roughness = 0.9
					copy.metallic = 0.0
					_prepared[material] = copy
					mesh_instance.set_surface_override_material(s, copy)
	for child in node.get_children():
		_prepare_materials(child)


static func item_model_id(item: ItemDef) -> String:
	## Esya -> asset kimligi: once birebir kimlik, sonra tag, sonra kategori.
	_ensure()
	var by_id: Dictionary = _item_rules.get("by_id", {})
	if by_id.has(item.id):
		return by_id[item.id]
	for rule: Variant in _item_rules.get("by_tag", []):
		if typeof(rule) == TYPE_ARRAY and rule.size() == 2 and item.has_tag(rule[0]):
			return rule[1]
	var by_category: Dictionary = _item_rules.get("by_category", {})
	return by_category.get(item.category, "toolbox")


static func weapon_model_id(weapon: WeaponDef) -> String:
	_ensure()
	var by_weapon: Dictionary = _item_rules.get("weapon_views", {})
	return by_weapon.get(weapon.id, "")
