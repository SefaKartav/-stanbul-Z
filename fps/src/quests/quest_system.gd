class_name QuestSystem
extends RefCounted
## Gorev omurgasi: DURUM MAKINESI + olay baglantilari + kayit.
##
## Veri: data/quests/quests.json. Ana gorevler SIRAYLA acilir (her gorevin
## hedefleri de sirayla), yan gorevler `requires` adimi bitince acilir ve
## birlikte ilerler. Hedef turleri:
##   event    -- olay sayaci (water_filled, craft, search, floor_reached, kill...)
##   state    -- dunya durumu (us sayisi, istasyon, rol, depo, dalga, tarla)
##   reach    -- konuma var (yaricap)
##   interact -- gorev nesnesiyle etkilesim: `needs` HARCANIR (keep: takim),
##               `gives` verilir, `defend` > 0 ise ardindan zombi dalgasi gelir
##               ve hepsi dusunce hedef tamamlanir
##   fetch    -- gorev esyasini al; kaybolursa ayni yerden YENIDEN alinir
##               (ana ilerleme kilitlenmez)
##   rescue   -- belirli kisiyi (profil) usse getir; kisi olurse baska bir
##               profil ayni hedefe atanir
##
## KONUMLAR gercek haritadan (OSM) KARARLI cozulur: ayni harita ayni noktayi
## verir. Kayitta konum degil gorev/hedef durumu tutulur.
##
## ODUL bir kez verilir: tamamlanan gorev kimligi kayda yazilir; kaydet/yukle
## ile ayni odul iki kez alinamaz (odul, tamamlanma ile ayni adimda).

signal quest_completed(quest_id: String)

const TICK := 0.5
const PROP_PREFIX := "gorev:"

var game: Node
var done: Dictionary = {}           # gorev kimligi -> true
var progress: Dictionary = {}       # gorev kimligi -> {step: int, counts: {hedef indeksi: sayi}}
var flags: Dictionary = {}          # dunya durumu bayraklari (water_line, network, bridge...)
var defend: Dictionary = {}         # "<gorev>:<hedef>" -> [zombi instance id]
var stats: Dictionary = {"floors_max": 0}
var _anchors: Dictionary = {}       # anchor metni -> Vector3 (INF: cozulemedi)
var _timer := 0.0
var _announced: Dictionary = {}


func _init(p_game: Node) -> void:
	game = p_game


static func localize(map_id: String) -> void:
	## Gorev metinleri ve yer kimlikleri yeni sabit harita icindir. Eski bir
	## haritada (eski kayit) oynaniyorsa gosterilen adlar geri cevrilir
	## (quests/place_roles.json). Her oyun kurulumunda DOSYA halinden
	## turetilir: ayni surecte iki harita acilsa cevirme birikmez.
	var roles: Dictionary = Content.place_roles.get(map_id, {})
	var pairs: Array = roles.get("text", [])
	Content.quests = _translate(Content.quests_source.duplicate(true), pairs) if not pairs.is_empty() \
		else Content.quests_source.duplicate(true)


static func _translate(node: Variant, pairs: Array) -> Variant:
	match typeof(node):
		TYPE_DICTIONARY:
			for key: Variant in node.keys():
				if str(key) in ["anchor", "id", "event", "item", "flag", "requires", "stage", "type", "profile", "recipe"]:
					continue
				node[key] = _translate(node[key], pairs)
		TYPE_ARRAY:
			for i in node.size():
				node[i] = _translate(node[i], pairs)
		TYPE_STRING:
			var text: String = node
			for pair: Array in pairs:
				text = text.replace(str(pair[0]), str(pair[1]))
			return text
	return node


# ---------------------------------------------------------------------------
# Veri
# ---------------------------------------------------------------------------
static func all_quests() -> Array:
	var list: Array = []
	for q: Dictionary in Content.quests.get("main", []):
		list.append(q)
	for q: Dictionary in Content.quests.get("side", []):
		list.append(q)
	return list


static func quest(id: String) -> Dictionary:
	for q: Dictionary in all_quests():
		if q.id == id:
			return q
	return {}


static func is_main(id: String) -> bool:
	return id.begins_with("m")


func active_main() -> Dictionary:
	for q: Dictionary in Content.quests.get("main", []):
		if not done.has(q.id):
			return q
	return {}


func active_side() -> Array:
	var list: Array = []
	for q: Dictionary in Content.quests.get("side", []):
		if done.has(q.id):
			continue
		if done.has(str(q.get("requires", ""))):
			list.append(q)
	return list


func active() -> Array:
	var list: Array = []
	var main := active_main()
	if not main.is_empty():
		list.append(main)
	list.append_array(active_side())
	return list


func _prog(q: Dictionary) -> Dictionary:
	if not progress.has(q.id):
		progress[q.id] = {"step": 0, "counts": {}}
	return progress[q.id]


func step_of(q: Dictionary) -> int:
	return int(_prog(q).step)


func objective(q: Dictionary) -> Dictionary:
	var objectives: Array = q.get("objectives", [])
	var s := step_of(q)
	return objectives[s] if s < objectives.size() else {}


# ---------------------------------------------------------------------------
# Dongu
# ---------------------------------------------------------------------------
func tick(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = TICK
	_track_floor()
	for q: Dictionary in active():
		if not _announced.has(q.id):
			_announced[q.id] = true
			if step_of(q) == 0 and _prog(q).counts.is_empty():
				game.hud.message("%s: %s" % ["YENI GOREV" if is_main(q.id) else "Yan gorev", q.title], Hud.ACCENT)
		_evaluate(q)
		_ensure_refetch(q)


func _ensure_refetch(q: Dictionary) -> void:
	## KILITLENME KORUMASI: aktif hedef bir GOREV esyasi istiyor ve oyuncuda
	## yoksa (dustu, oldu, satti), esyanin ilk alindigi yerde yedegi belirir.
	var obj := objective(q)
	for need: Dictionary in obj.get("needs", []):
		if not need.has("item") or bool(_prog(q).counts.get("paid", false)):
			continue
		var def: ItemDef = Content.item(str(need.item))
		if def == null or not def.has_tag("quest") or game.inventory.count(def.id) > 0:
			continue
		var source := _fetch_source(def.id)
		if source.is_empty():
			continue
		var id := PROP_PREFIX + "yedek:" + def.id
		if game.props.by_id.has(id) and not game.props.get_entry(id).get("removed", false):
			continue
		var p := anchor(str(source.anchor))
		if p == Vector3.INF:
			continue
		game.props.by_id.erase(id)
		game.props.add({"id": id, "asset": str(source.asset), "pos": p, "kind": "mission",
			"label": "Yedek: %s" % def.name, "data": {"refetch": def.id}})
		game.hud.message("%s kayip -- ilk bulundugu yerde bir yedegi var (haritada)." % def.name, Hud.ACCENT)
	# Esya geri alindiysa yedek nesnesi kalkar.
	for e: Dictionary in game.props.entries:
		var r := str(e.get("data", {}).get("refetch", ""))
		if r != "" and not e.get("removed", false) and game.inventory.count(r) > 0:
			game.props.remove(str(e.id))


static func _fetch_source(item_id: String) -> Dictionary:
	for q: Dictionary in all_quests():
		for obj: Dictionary in q.get("objectives", []):
			if str(obj.get("type", "")) == "fetch" and str(obj.get("item", "")) == item_id:
				return obj
	return {}


func _evaluate(q: Dictionary) -> void:
	var obj := objective(q)
	if obj.is_empty():
		_complete(q)
		return
	var key := "%s:%d" % [q.id, step_of(q)]
	match str(obj.type):
		"state":
			if _state_ok(obj):
				_advance(q)
		"reach":
			var p := anchor(str(obj.anchor))
			if p != Vector3.INF and Vector2(p.x, p.z).distance_to(Vector2(game.player.global_position.x, game.player.global_position.z)) \
					<= float(obj.get("radius", 10.0)):
				_advance(q)
		"interact", "fetch":
			_ensure_prop(q, obj, key)
			if str(obj.type) == "fetch" and game.inventory.count(str(obj.item)) > 0:
				_advance(q)
			elif defend.has(key):
				_check_defend(q, key)
		"rescue":
			_ensure_rescue(q, obj)
			if game.bases.colony.residents.has(str(_rescue_profile(q, obj))):
				_advance(q)


func _advance(q: Dictionary) -> void:
	var prog := _prog(q)
	var obj := objective(q)
	if obj.has("label"):
		game.hud.message("Tamamlandi: %s" % obj.label, Hud.GREEN)
	game.props.remove(PROP_PREFIX + "%s:%d" % [q.id, int(prog.step)])
	prog.step = int(prog.step) + 1
	prog.counts = {}
	if objective(q).is_empty():
		_complete(q)
	else:
		_update_waypoint()


func _complete(q: Dictionary) -> void:
	if done.has(q.id):
		return
	done[q.id] = true      # ODUL ILE AYNI ADIMDA: tekrar verilmez
	var rewards: Dictionary = q.get("rewards", {})
	var parts := PackedStringArray()
	if rewards.has("xp"):
		game.progression.award_source(float(rewards.xp), "quest")
		parts.append("+%d deneyim" % int(rewards.xp))
	for entry: Array in rewards.get("items", []):
		var def: ItemDef = Content.item(str(entry[0]))
		if def == null:
			continue
		_give(ItemStack.new(def, int(entry[1]), 55.0), "Gorev odulu")
		parts.append("%s x%d" % [def.name, int(entry[1])])
	for recipe_id: Variant in rewards.get("unlock", []):
		game.crafting.known_recipes[str(recipe_id)] = true
		var recipe: RecipeDef = Content.recipes.get(str(recipe_id))
		parts.append("sema: %s" % (recipe.name if recipe != null else str(recipe_id)))
	if rewards.has("points"):
		game.progression.points += int(rewards.points)
		parts.append("+%d beceri puani" % int(rewards.points))
	if rewards.has("flag"):
		flags[str(rewards.flag)] = true
		_on_flag(str(rewards.flag))
	if rewards.has("rescue"):
		var profile := str(rewards.rescue)
		if not game.bases.settlements.is_empty() and not game.bases.colony.residents.has(profile):
			var base: Settlement = game.bases.settlements[0]
			game.survivors.overrides[profile] = game.free_spot(base.centre() + Vector3(4, 0.2, 4))
			parts.append("%s ussunun kapisinda bekliyor" % Content.colony.profiles.get(profile, {}).get("name", profile))
	game.hud.message("GOREV TAMAM: %s  (%s)" % [q.title, ", ".join(parts)], Hud.GREEN)
	game.sfx.play_ui("craft_done")
	quest_completed.emit(q.id)
	_update_waypoint()
	if str(rewards.get("flag", "")) == "campaign_done":
		game.call_deferred("show_campaign_result")


func _give(stack: ItemStack, label: String) -> void:
	var left: int = game.inventory.add(stack.copy())
	if left > 0:
		game.pickups.spawn([stack.copy(left)], game.player.global_position + Vector3(0, 0.2, 0), label, "remnant")
		game.hud.message("%s cantaya sigmadi, ayaginin dibinde" % stack.definition.name, Hud.ACCENT)


func _on_flag(flag: String) -> void:
	match flag:
		"water_line":
			game.hud.message("Moda terfi istasyonu calisiyor: usler her gun hattan su alacak (yine de aritin).", Hud.BLUE)
		"network":
			game.hud.message("TELSIZ AGI ACIK: bekleyen herkes telsizde gorunur, yardim cagrilari gelecek.", Hud.BLUE)
		"bridge":
			game.hud.message("Kopru gecisi guvende. Avrupa yakasi ikmal hattina acik.", Hud.BLUE)


func on_new_day(day: int) -> void:
	## Dunya durumunun gunluk etkileri.
	if flags.has("water_line") and not game.bases.settlements.is_empty():
		for base: Settlement in game.bases.settlements:
			var amount := 4 if flags.has("grid") else 3
			base.stockpile.add(ItemStack.new(Content.item("water_dirty"), amount, 0.0))
		game.hud.message("Su hattindan uslere kirli su geldi", Hud.BLUE)


# ---------------------------------------------------------------------------
# Olaylar
# ---------------------------------------------------------------------------
func notify(event: String, data: Dictionary = {}) -> void:
	for q: Dictionary in active():
		var obj := objective(q)
		if obj.is_empty() or str(obj.type) != "event" or str(obj.event) != event:
			continue
		if event == "craft" and obj.has("recipes") and not str(data.get("recipe", "")) in obj.recipes:
			continue
		if event == "search" and obj.has("classes") and not str(data.get("class", "")) in obj.classes:
			continue
		if event == "floor_reached" and int(data.get("floor", 0)) < int(obj.get("min_floor", 0)):
			continue
		var prog := _prog(q)
		var n := int(prog.counts.get("n", 0)) + int(data.get("count", 1))
		prog.counts["n"] = n
		if n >= int(obj.get("count", 1)):
			_advance(q)


func _track_floor() -> void:
	## Oyuncunun bulundugu bina kati (ilk ziyaretler ve "ust kata cik" hedefi).
	if not game.generator is CityGenerator:
		return
	var city: CityGenerator = game.generator
	var p: Vector3 = game.player.global_position
	var index := city.building_at(floori(p.x), floori(p.z))
	if index < 0:
		return
	var b: Dictionary = city.buildings[index]
	var k := floori((p.y - float(b.base_y) + 0.3) / CityGenerator.FLOOR_HEIGHT)
	if k >= 1 and p.y < float(b.top_y) + 0.5:
		notify("floor_reached", {"floor": k})
		if k > int(stats.floors_max):
			stats.floors_max = k
			if k >= 2:
				game.progression.award_source(10.0 * k, "discovery")


# ---------------------------------------------------------------------------
# Durum kontrolleri
# ---------------------------------------------------------------------------
func _state_ok(obj: Dictionary) -> bool:
	var bases: Array = game.bases.settlements
	match str(obj.check):
		"bases":
			return bases.size() >= int(obj.value)
		"bases_apart":
			for i in bases.size():
				for j in range(i + 1, bases.size()):
					if (bases[i] as Settlement).centre().distance_to((bases[j] as Settlement).centre()) >= float(obj.value):
						return true
			return false
		"station_in_base":
			for entry: Dictionary in game.placeables.entries:
				if entry.kind == "station" and str(entry.station) == str(obj.value):
					for base: Settlement in bases:
						if base.contains_position(Vector3(entry.cell)):
							return true
			return false
		"role":
			for r: Dictionary in game.bases.colony.residents.values():
				if str(r.get("role", "")) == str(obj.value) and float(r.get("health", 0.0)) > 0.0:
					return true
			return false
		"building_role":
			for base: Settlement in bases:
				if not base.buildings_with(str(obj.value)).is_empty():
					return true
			return false
		"stock_tag":
			var i := int(obj.get("base", 0))
			return i < bases.size() and (bases[i] as Settlement).stockpile.count_by_tag(str(obj.tag)) >= int(obj.value)
		"stock_item":
			var i := int(obj.get("base", 0))
			return i < bases.size() and (bases[i] as Settlement).stockpile.count(str(obj.item)) >= int(obj.value)
		"waves_survived":
			return int(game.waves.survived) >= int(obj.value)
		"fields":
			return game.bases.colony.fields.size() >= int(obj.value)
		"colonists":
			return game.bases.colony.residents.size() >= int(obj.value)
	return false


# ---------------------------------------------------------------------------
# Gorev nesneleri, etkilesim, savunma
# ---------------------------------------------------------------------------
func _ensure_prop(q: Dictionary, obj: Dictionary, key: String) -> void:
	var id := PROP_PREFIX + key
	if game.props.by_id.has(id) and not game.props.get_entry(id).get("removed", false):
		return
	var p := anchor(str(obj.anchor))
	if p == Vector3.INF:
		return
	var entry := {"id": id, "asset": str(obj.asset), "pos": p, "kind": "mission", "label": str(obj.label),
		"data": {"quest": q.id, "key": key}}
	if str(obj.anchor).begins_with("roof:"):
		entry["snapped"] = true       # cati: konum kesin, zemine oturtulmaz
	game.props.by_id.erase(id)
	game.props.add(entry)


func interaction_for(prop: Dictionary, key_label: String) -> Dictionary:
	var data: Dictionary = prop.get("data", {})
	if data.has("refetch"):
		return {"kind": "mission", "prop": prop, "quest": "", "refetch": str(data.refetch),
			"prompt": "[%s] Al: %s" % [key_label, prop.label]}
	var q := quest(str(data.get("quest", "")))
	if q.is_empty() or done.has(q.id):
		return {}
	var obj := objective(q)
	if obj.is_empty() or "%s:%d" % [q.id, step_of(q)] != str(data.get("key", "")):
		return {}
	var key := str(data.key)
	if defend.has(key):
		return {"kind": "none", "prompt": "%s -- saldiriyi puskurt (%d kaldi)" % [obj.label, _alive(key)]}
	var paid := bool(_prog(q).counts.get("paid", false))
	var missing := PackedStringArray() if paid else _missing(obj)
	var verb := "Al" if str(obj.type) == "fetch" else ("Savunmayi yeniden baslat" if paid else "Kullan")
	var text := "[%s] %s: %s" % [key_label, verb, obj.label]
	if not missing.is_empty():
		text = "%s -- EKSIK: %s" % [obj.label, ", ".join(missing)]
		return {"kind": "none", "prompt": text}
	return {"kind": "mission", "prop": prop, "quest": q.id, "prompt": text}


func _missing(obj: Dictionary) -> PackedStringArray:
	var result := PackedStringArray()
	for need: Dictionary in obj.get("needs", []):
		var have: int = game.inventory.count_by_tag(str(need.tag)) if need.has("tag") else game.inventory.count(str(need.item))
		if have < int(need.count):
			var name := str(Content.ui_names.get("tags", {}).get(need.tag, need.tag)) if need.has("tag") \
				else Content.item(str(need.item)).name
			result.append("%dx %s" % [int(need.count) - have, name])
	return result


func interact(interaction: Dictionary) -> void:
	if interaction.has("refetch"):
		var def: ItemDef = Content.item(str(interaction.refetch))
		if game.inventory.add(ItemStack.new(def, 1, 60.0)) > 0:
			game.hud.message("Cantada yer yok -- once yer ac", Hud.RED)
			return
		game.hud.message("Alindi: %s" % def.name, Hud.GREEN)
		game.props.remove(str(interaction.prop.id))
		return
	var q := quest(str(interaction.quest))
	var obj := objective(q)
	if obj.is_empty():
		return
	var key := "%s:%d" % [q.id, step_of(q)]
	var duration := float(obj.get("time", 2.0))
	game._action = {"label": str(obj.label), "duration": duration, "elapsed": 0.0,
		"origin": game.player.global_position, "done": _finish_interact.bind(q.id, key)}


func _finish_interact(quest_id: String, key: String) -> void:
	var q := quest(quest_id)
	var obj := objective(q)
	if obj.is_empty() or "%s:%d" % [q.id, step_of(q)] != key:
		return
	var paid := bool(_prog(q).counts.get("paid", false))
	if not paid and not _missing(obj).is_empty():
		game.hud.message("Eksik malzeme", Hud.RED)
		return
	# ATOMIK: once kopyada harca + ver; sigmazsa hicbir sey olmaz. Savunma
	# yarim kaldiysa (kayit/yukleme, olum) ihtiyac IKINCI KEZ harcanmaz.
	var trial: Inventory = game.inventory.clone()
	for need: Dictionary in obj.get("needs", []):
		if bool(need.get("keep", false)) or paid:
			continue
		if need.has("tag"):
			var left := int(need.count)
			for stack: ItemStack in trial.matching_tag(str(need.tag)):
				var take := mini(left, stack.quantity)
				trial.take_from_stack(stack, take)
				left -= take
				if left <= 0:
					break
		else:
			trial.remove(str(need.item), int(need.count))
	if str(obj.type) == "fetch":
		if trial.add(ItemStack.new(Content.item(str(obj.item)), 1, 60.0)) > 0:
			game.hud.message("Cantada yer yok -- once yer ac", Hud.RED)
			return
	game.inventory.replace_with(trial)
	if paid and str(obj.type) != "fetch" and int(obj.get("defend", 0)) > 0:
		_start_defend(q, key, int(obj.get("defend", 0)))
		return
	if str(obj.type) != "fetch":
		_prog(q).counts["paid"] = true
	for entry: Array in obj.get("gives", []):
		var def: ItemDef = Content.item(str(entry[0]))
		if def != null:
			_give(ItemStack.new(def, int(entry[1]), 60.0), obj.label)
	if str(obj.type) == "fetch":
		game.hud.message("Alindi: %s" % Content.item(str(obj.item)).name, Hud.GREEN)
		return            # _evaluate envanterde gorunce ilerletir
	var waves := int(obj.get("defend", 0))
	if waves > 0:
		_start_defend(q, key, waves)
		return
	_advance(q)


func _start_defend(q: Dictionary, key: String, count: int) -> void:
	var entry: Dictionary = game.props.get_entry(PROP_PREFIX + key)
	var center: Vector3 = entry.get("pos", game.player.global_position)
	var ids: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var pool := ["walker", "walker", "runner", "walker", "brute", "screamer"] if is_main(q.id) else ["walker", "runner"]
	for i in count:
		var a := TAU * i / count + rng.randf_range(-0.2, 0.2)
		var d := rng.randf_range(20.0, 32.0)
		var cell := Vector2i(floori(center.x + cos(a) * d), floori(center.z + sin(a) * d))
		var y := int(game.generator.ground_height(cell.x, cell.y))
		var def: ZombieDef = Content.zombies.get(pool[i % pool.size()])
		if def == null:
			continue
		var z: Zombie = game.zombies.spawn(def, Vector3(cell.x + 0.5, y + 0.2, cell.y + 0.5))
		if z != null:
			z.set_meta("quest_target", true)
			ids.append(z.get_instance_id())
	defend[key] = ids
	game.on_noise_at(center, 120.0)
	game.hud.message("SALDIRI! %d zombi sesi duydu -- noktayi savun." % ids.size(), Hud.RED)


func _alive(key: String) -> int:
	var n := 0
	for id: int in defend.get(key, []):
		var z: Object = instance_from_id(id)
		if z != null and is_instance_valid(z) and (z as Zombie).is_alive():
			n += 1
	return n


func _check_defend(q: Dictionary, key: String) -> void:
	if _alive(key) == 0:
		defend.erase(key)
		game.hud.message("Saldiri puskurtuldu.", Hud.GREEN)
		_advance(q)


func _rescue_profile(q: Dictionary, obj: Dictionary) -> String:
	## Hedef kisi olduyse ayni gorevi baska (henuz kurtarilmamis) biri ustlenir.
	var profile := str(obj.profile)
	var r: Dictionary = game.bases.colony.residents.get(profile, {})
	if game.survivors.rescued.has(profile) and (r.is_empty() or float(r.get("health", 0.0)) <= 0.0):
		var prog := _prog(q)
		if prog.counts.has("alt"):
			return str(prog.counts.alt)
		for other: String in Content.colony.profiles:
			if not game.survivors.rescued.has(other) and not game.bases.colony.residents.has(other):
				prog.counts["alt"] = other
				game.hud.message("%s olmustu; %s ayni yerde yardim bekliyor." % [
					Content.colony.profiles[profile].name, Content.colony.profiles[other].name], Hud.ACCENT)
				return other
	return profile


func _ensure_rescue(q: Dictionary, obj: Dictionary) -> void:
	var profile := _rescue_profile(q, obj)
	if game.survivors.overrides.has(profile):
		return
	var p := anchor(str(obj.anchor))
	if p != Vector3.INF:
		game.survivors.overrides[profile] = p


# ---------------------------------------------------------------------------
# Konum cozumleme (kararli)
# ---------------------------------------------------------------------------
func anchor(spec: String) -> Vector3:
	if _anchors.has(spec):
		return _anchors[spec]
	var p := _resolve(spec)
	_anchors[spec] = p
	return p


func _place(name: String) -> Vector2:
	if not game.generator is CityGenerator:
		return Vector2(game.player.global_position.x, game.player.global_position.z)
	var city: CityGenerator = game.generator
	var places: Dictionary = city.data.get("places", {})
	# Eski harita: yeni POI kimligi -> o haritadaki yer adi.
	name = str(Content.place_roles.get(city.map_id, {}).get("places", {}).get(name, name))
	if places.has(name):
		return Vector2(float(places[name][0]), float(places[name][1]))
	# Kucuk test haritasi: adlandirilmis yer yok; dogus noktasi kullanilir.
	var s: Array = (game.generator as CityGenerator).data.get("spawn", [0, 0])
	return Vector2(float(s[0]), float(s[1]))


func _resolve(spec: String) -> Vector3:
	var parts := spec.split(":")
	if not game.generator is CityGenerator:
		return Vector3.INF
	var city: CityGenerator = game.generator
	match parts[0]:
		"place":
			var c := _place(parts[1])
			return Vector3(c.x, city.surface_y(floori(c.x), floori(c.y)), c.y)
		"water":
			var c := _place(parts[1])
			var best := Vector3.INF
			for e: Dictionary in game.props.entries:
				if e.kind == "water_source" and (best == Vector3.INF or Vector2(e.pos.x, e.pos.z).distance_to(c) < Vector2(best.x, best.z).distance_to(c)):
					best = e.pos
			return best
		"base":
			var i := int(parts[1])
			if i < game.bases.settlements.size():
				return (game.bases.settlements[i] as Settlement).centre()
			return Vector3.INF
		"bridge":
			if city.bridges.is_empty():
				return Vector3.INF
			var b: Dictionary = city.bridges[0]
			var pts: PackedVector2Array = b.pts
			var a := pts[0]
			var z := pts[pts.size() - 1]
			var asia := a if a.distance_to(_place("carsibasi_meydan")) < z.distance_to(_place("carsibasi_meydan")) else z
			var europe := z if asia == a else a
			var p := asia if parts[1] == "asia" else europe
			# Tabliye ucundan karaya dogru 12 m: kontrol noktasi kopru basinda.
			var inward := (p - (europe if parts[1] == "asia" else asia)).normalized()
			var q := p + inward * 12.0
			return Vector3(q.x, city.surface_y(floori(q.x), floori(q.y)), q.y)
		"class":
			return _building_anchor(city, parts[1].split("|"), _place(parts[2]), int(parts[3]) if parts.size() > 3 else 0)
		"roof":
			return _roof_anchor(city, int(parts[1]), _place(parts[2]))
	return Vector3.INF


func _building_anchor(city: CityGenerator, classes: PackedStringArray, near: Vector2, rank: int) -> Vector3:
	## Siniflardan birindeki, ic mekani olan, oynanabilir koridordaki binalar
	## yakindan uzaga; `rank`inci binanin kapisinin hemen ici (zemin kat).
	var found: Array = []
	for radius: float in [300.0, 900.0, 2500.0, 8000.0]:
		found.clear()
		for index: int in city.buildings_near(Vector3(near.x, 0, near.y), radius):
			var b: Dictionary = city.buildings[index]
			if not str(b["class"]) in classes or not bool(b.interior):
				continue
			var c: Vector2 = b.centroid
			if not game.world.is_open_column(floori(c.x), floori(c.y)):
				continue
			found.append(index)
		if found.size() > rank:
			break
	found.sort_custom(func(a: int, b: int) -> bool:
		var da: float = (city.buildings[a].centroid as Vector2).distance_to(near)
		var db: float = (city.buildings[b].centroid as Vector2).distance_to(near)
		return da < db if absf(da - db) > 0.01 else a < b)
	for i in range(rank, found.size()):
		var plan := city.interior_plan(found[i])
		if not plan.get("ok", false):
			continue
		var door: Dictionary = plan.doors[0]
		var inside: Vector2i = door.cell - door.outward * 2
		return Vector3(inside.x + 0.5, float(plan.floors[0].y), inside.y + 0.5)
	return Vector3(near.x, city.surface_y(floori(near.x), floori(near.y)), near.y)


func _roof_anchor(city: CityGenerator, min_levels: int, near: Vector2) -> Vector3:
	## En az `min_levels` katli, merdiveni CATIYA acilan en yakin bina: cati
	## cikisinin yanindaki hucre (gercek merdivenle ulasilir).
	var candidates: Array = []
	for radius: float in [400.0, 1200.0, 3000.0, 8000.0]:
		candidates.clear()
		for index: int in city.buildings_near(Vector3(near.x, 0, near.y), radius):
			var b: Dictionary = city.buildings[index]
			if bool(b.interior) and int(b.levels) >= min_levels and not bool(b.pitched) \
					and game.world.is_open_column(floori(b.centroid.x), floori(b.centroid.y)):
				candidates.append(index)
		if not candidates.is_empty():
			break
	candidates.sort_custom(func(a: int, b: int) -> bool:
		var da: float = (city.buildings[a].centroid as Vector2).distance_to(near)
		var db: float = (city.buildings[b].centroid as Vector2).distance_to(near)
		return da < db if absf(da - db) > 0.01 else a < b)
	for index: int in candidates.slice(0, 25):
		var plan := city.interior_plan(index)
		var stairs: Dictionary = plan.get("stairs", {})
		if not plan.get("ok", false) or stairs.is_empty() or not bool(stairs.roof):
			continue
		var b: Dictionary = city.buildings[index]
		var exit: Vector2i = stairs.exit
		# Cati cikisindan bir hucre oteye (korkulugun disina degil, catinin ustune).
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1)]:
			var c: Vector2i = exit + d * 2
			if city.building_at(c.x, c.y) == index and not stairs.tops.has(c) and not stairs.pillar.has(c) \
					and not city.column_info(c.x, c.y).edge:
				return Vector3(c.x + 0.5, float(b.top_y) + 1.0, c.y + 0.5)
		return Vector3(exit.x + 0.5, float(b.top_y) + 1.0, exit.y + 0.5)
	return Vector3.INF


# ---------------------------------------------------------------------------
# Arayuz
# ---------------------------------------------------------------------------
func hud_line() -> String:
	var q := active_main()
	if q.is_empty():
		return "Ana hedef tamam -- sehir hala senin (J: gunluk)" if done.has("m24") else ""
	var obj := objective(q)
	if obj.is_empty():
		return ""
	var text := "%s: %s" % [q.title, obj.get("label", "")]
	text += _progress_text(q, obj)
	var p := objective_position(q)
	if p != Vector3.INF:
		var d := Vector2(p.x, p.z).distance_to(Vector2(game.player.global_position.x, game.player.global_position.z))
		text += "  (%s)" % (("%.1f km" % (d / 1000.0)) if d >= 1000.0 else ("%d m" % int(d)))
	return text


func _progress_text(q: Dictionary, obj: Dictionary) -> String:
	if str(obj.type) == "event" and int(obj.get("count", 1)) > 1:
		return " %d/%d" % [int(_prog(q).counts.get("n", 0)), int(obj.count)]
	return ""


func objective_position(q: Dictionary) -> Vector3:
	var obj := objective(q)
	if obj.is_empty() or not obj.has("anchor"):
		return Vector3.INF
	return anchor(str(obj.anchor))


func _update_waypoint() -> void:
	var q := active_main()
	if q.is_empty():
		return
	var p := objective_position(q)
	if p != Vector3.INF:
		game.waypoint = p


func journal_entries() -> Array:
	## Gunluk ekrani icin: [{id, title, stage, text, objectives:[{label, state}], rewards, main, done}]
	var result: Array = []
	var stage_names := {}
	for s: Dictionary in Content.quests.get("stages", []):
		stage_names[s.id] = s.name
	for q: Dictionary in all_quests():
		var is_done := done.has(q.id)
		var available: bool = is_done or (is_main(q.id) and q.id == str(active_main().get("id", ""))) \
			or (not is_main(q.id) and done.has(str(q.get("requires", ""))))
		if not available:
			continue
		var objs: Array = []
		var s := step_of(q)
		var list: Array = q.get("objectives", [])
		for i in list.size():
			var o: Dictionary = list[i]
			var state := "done" if is_done or i < s else ("active" if i == s else "locked")
			var label := str(o.get("label", ""))
			if state == "active":
				label += _progress_text(q, o)
				var miss := _missing(o)
				if not miss.is_empty():
					label += "  [eksik: %s]" % ", ".join(miss)
			objs.append({"label": label, "state": state})
		result.append({"id": q.id, "title": q.title, "stage": stage_names.get(q.get("stage", ""), "Yan gorev"),
			"text": q.get("text", ""), "objectives": objs, "rewards": q.get("rewards", {}),
			"main": is_main(q.id), "done": is_done, "position": objective_position(q) if not is_done else Vector3.INF})
	return result


# ---------------------------------------------------------------------------
# Kayit
# ---------------------------------------------------------------------------
func to_dict() -> Dictionary:
	return {"done": done.keys(), "progress": progress.duplicate(true), "flags": flags.keys(),
		"stats": stats.duplicate(), "overrides": _override_dict()}


func _override_dict() -> Dictionary:
	var out := {}
	for profile: String in game.survivors.overrides:
		var p: Vector3 = game.survivors.overrides[profile]
		out[profile] = [p.x, p.y, p.z]
	return out


func load_dict(data: Dictionary) -> void:
	done.clear()
	for id: Variant in data.get("done", []):
		done[str(id)] = true
	progress = data.get("progress", {}).duplicate(true)
	for id: String in progress:
		progress[id]["step"] = int(progress[id].get("step", 0))
		progress[id]["counts"] = progress[id].get("counts", {})
	flags.clear()
	for f: Variant in data.get("flags", []):
		flags[str(f)] = true
	stats = data.get("stats", {"floors_max": 0}).duplicate()
	for profile: String in data.get("overrides", {}):
		var p: Array = data.overrides[profile]
		game.survivors.overrides[profile] = Vector3(p[0], p[1], p[2])
	_announced.clear()
	defend.clear()       # yarim kalan savunma: etkilesim yeniden baslatir
	_update_waypoint()
