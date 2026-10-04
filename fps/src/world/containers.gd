class_name ContainerRegistry
extends RefCounted
## Aranabilir mobilyalarin KALICI durumu (dolap, raf, cekmece, sandik).
##
## KURALLAR (data/world/containers.json)
##   * Kimlik planla gelir: "<bina>:f<kat>:s<sira>". Chunk yukleme sirasina,
##     dugum kimligine ya da gecici dizi sirasina bagli degildir.
##   * ZAR BIR KEZ ATILIR: ilk arama tamamlaninca icerik uretilir ve saklanir.
##     Paneli kapatmak, aramayi kesmek, kayit yuklemek ya da bolgeden
##     uzaklasmak yeniden zar attirmaz. Zar tohumu kimlikten turer; eski bir
##     kaydi yukleyip yeniden aramak da farkli sonuc vermez.
##   * KESINTI: arama ilerlemesi (0..1) container'da kalir; geri gelince
##     kaldigi yerden surer. Kesilen aramada HIC esya verilmez (eski kismi
##     bina aramasindaki "yarida kalanlar" odulu tasinmadi).
##   * BINA BUTCESI: sinifin toplam cekilis butcesi container'lara `share`
##     agirligiyla dagitilir; container sayisi ekonomiyi katlamaz. Bazi
##     container'lar bastan bostur ("onceden yagmalanmis"); `basic` tipler
##     (mutfak, ecza, market rafi) hic bos baslamaz.
##   * YENILENME: bina ilk yagmalandiginda saat baslar; her `restock_days`
##     gunde bir jeton birikir (en fazla `restock_max_tokens`). Jeton YALNIZCA
##     bos bir container'da yeni arama BASLATILDIGINDA harcanir: acip kapamak
##     ya da chunk yuklemek yenilemez, acik paneldeki icerik ezilmez.
##   * TAHRIP: container kirilirsa (silahla) kalan icerik BIR KEZ yerde enkaz
##     yigini olur; alinmis esya geri gelmez.

var city: CityGenerator
var states: Dictionary = {}          # container id -> durum
var building_clock: Dictionary = {}  # bina id -> {t0, used}
var _alloc_cache: Dictionary = {}    # bina id -> {container id: cekilis}
var _building_index: Dictionary = {} # bina id -> indeks


func _init(p_city: CityGenerator) -> void:
	city = p_city


static func rules() -> Dictionary:
	return Content.containers


static func type_def(type_id: String) -> Dictionary:
	return Content.containers.get("types", {}).get(type_id, {})


var migrated: Dictionary = {}        # bina id -> eski kayitta aranmis dolap sayisi (olcek gocu)


func state(id: String) -> Dictionary:
	if not states.has(id) and not migrated.is_empty():
		_apply_migration(id)
	return states.get(id, {})


func _state_mut(id: String) -> Dictionary:
	if not states.has(id) and not migrated.is_empty():
		_apply_migration(id)
	if not states.has(id):
		states[id] = {"r": false, "items": [], "p": 0.0, "o": false, "d": false, "n": 0, "day": 0}
	return states[id]


func _apply_migration(id: String) -> void:
	## Olcek gocu: eski kayitta N dolabi aranmis binanin zemin katindaki ilk N
	## dolabi (sira numarasiyla, kararli) aranmis ve BOS gelir. Ikinci kez odul yok.
	var bid := id.get_slice(":f", 0)
	if not migrated.has(bid):
		return
	var rest := id.substr(bid.length() + 2)       # "<kat>:s<sira>"
	var floor_index := int(rest.get_slice(":", 0))
	var slot_text := rest.get_slice(":", 1)
	if floor_index != 0 or not slot_text.begins_with("s"):
		return
	if int(slot_text.substr(1)) < int(migrated[bid]):
		states[id] = {"r": true, "items": [], "p": 0.0, "o": false, "d": false, "n": 0, "day": 0}


func is_unlocked(id: String) -> bool:
	return bool(state(id).get("u", false))


func unlock(id: String) -> void:
	_state_mut(id)["u"] = true


func status(f: Dictionary) -> String:
	## "unsearched" | "items" | "empty" | "destroyed"
	var s := state(f.id)
	if s.is_empty() or not s.r:
		return "destroyed" if s.get("d", false) else "unsearched"
	if s.d:
		return "destroyed"
	return "items" if not s.items.is_empty() else "empty"


func items(id: String) -> Array:
	return state(id).get("items", [])


# ---------------------------------------------------------------------------
# Butce ve zar
# ---------------------------------------------------------------------------
func allocation(plan: Dictionary) -> Dictionary:
	## Bina butcesinin container'lara dagitimi (deterministik).
	var bid: String = plan.id
	if _alloc_cache.has(bid):
		return _alloc_cache[bid]
	var r := rules()
	# KAT BASINA butce: katin kullanimi (zemin dukkan, ust kat konut) x alan
	# (azalan artis) x kat sirasi (azalan artis) x semt. 12 katli apartman
	# buyuk ama bufeden 12 kat fazla degil; container sayisi butceyi katlamaz.
	var by_floor := {}
	for f: Dictionary in plan.furniture:
		if f.container == "":
			continue
		var k := int(f.floor)
		if not by_floor.has(k):
			by_floor[k] = []
		by_floor[k].append(f)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(bid + ":butce")
	var result := {}
	var empty_chance := float(r.get("empty_chance", 0.15))
	for k: int in by_floor:
		_allocate_floor(plan, k, by_floor[k], rng, empty_chance, result)
	_alloc_cache[bid] = result
	return result


func floor_budget(plan: Dictionary, k: int) -> float:
	var r := rules()
	var fl: Dictionary = plan.floors[k] if k < plan.floors.size() else {}
	var use := str(fl.get("use", plan["class"]))
	var budget := float(r.get("class_budget", {}).get(use, r.get("class_budget", {}).get(plan["class"], 5)))
	var cells := 0
	for room: Dictionary in fl.get("rooms", []):
		cells += int(room.get("area", 0))
	var area_factor := clampf(sqrt(maxf(1.0, cells) / 80.0), 0.6, 2.0)
	return budget * area_factor / (1.0 + 0.35 * k) * region_factor(plan)


func building_budget(plan: Dictionary) -> float:
	var total := 0.0
	for k in mini(int(plan.accessible), plan.floors.size()):
		total += floor_budget(plan, k)
	return total


func region_factor(plan: Dictionary) -> float:
	## Semtin ganimet carpani (regions.json), yumusatilmis: sqrt.
	if city == null or not plan.has("index") or int(plan.index) >= city.buildings.size():
		return 1.0
	var c: Vector2 = city.buildings[int(plan.index)].centroid
	var geo := city.geo.inverse(c)
	var best := 1.0
	var best_d := INF
	for id: String in Content.regions:
		var region: Dictionary = Content.regions[id]
		if not region.has("lat"):
			continue
		var d := Vector2(float(region.lat) - geo.y, (float(region.lon) - geo.x) * 0.75).length()
		if d < best_d:
			best_d = d
			best = float(region.get("loot_multiplier", 1.0))
	return sqrt(clampf(best, 0.5, 2.0))


func _allocate_floor(plan: Dictionary, k: int, items: Array, rng: RandomNumberGenerator, empty_chance: float,
		result: Dictionary) -> void:
	var budget := floor_budget(plan, k)
	var list: Array = []
	var total_share := 0.0
	for f: Dictionary in items:
		var share := float(type_def(f.container).get("share", 1.0))
		list.append([f, share])
		total_share += share
	for pair: Array in list:
		var f: Dictionary = pair[0]
		var expected: float = budget * pair[1] / maxf(0.01, total_share)
		var rolls := floori(expected) + (1 if rng.randf() < expected - floorf(expected) else 0)
		var basic := bool(type_def(f.container).get("basic", false))
		if basic:
			rolls = maxi(1, rolls)
		elif rng.randf() < empty_chance:
			rolls = 0
		result[f.id] = rolls


func roll(plan: Dictionary, f: Dictionary, day: int, luck: float = 0.0) -> void:
	## Ilk arama tamamlandi: zar BIR KEZ atilir.
	var s := _state_mut(f.id)
	if s.r:
		return
	var rolls: int = allocation(plan).get(f.id, 0)
	s.items = _roll_items(f, rolls, hash(f.id + ":0"), luck, true)
	s.r = true
	s.p = 0.0
	s.day = day
	if not building_clock.has(plan.id):
		building_clock[plan.id] = {"t0": day, "used": 0}


func _roll_items(f: Dictionary, rolls: int, seed_value: int, luck: float, first: bool) -> Array:
	var def := type_def(f.container)
	var pools: Array = def.get("pools", [])
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var bag := Inventory.new(99999.0, 999)
	for i in rolls:
		var pool_id := _pick_pool(pools, rng, first and i == 0 and bool(def.get("basic", false)))
		var table: LootTable = Content.loot_tables.get(pool_id)
		if table == null:
			continue
		var stack := pick_entry(table, rng, luck)
		if stack != null:
			bag.add(stack)
	return bag.stacks


static func _pick_pool(pools: Array, rng: RandomNumberGenerator, main_only: bool) -> String:
	## `basic` container'in ILK cekilisi ana havuzdan: temel ihtiyac asiri
	## sansa bagli kalmasin (mutfakta yiyecek, ecza dolabinda ilac).
	if pools.is_empty():
		return ""
	if main_only:
		return str(pools[0][0])
	var total := 0.0
	for pool: Array in pools:
		total += float(pool[1])
	var pick := rng.randf() * total
	for pool: Array in pools:
		pick -= float(pool[1])
		if pick <= 0.0:
			return str(pool[0])
	return str(pools[pools.size() - 1][0])


static func pick_entry(table: LootTable, rng: RandomNumberGenerator, luck: float = 0.0) -> ItemStack:
	## Tablodan TEK giris (tablonun kendi cekilis sayisindan bagimsiz).
	var total := table.total_weight()
	if total <= 0.0:
		return null
	var pick := rng.randf_range(0.0, total)
	for entry: Dictionary in table.entries:
		pick -= entry.weight
		if pick > 0.0:
			continue
		var definition: ItemDef = Content.items.get(entry.item)
		if definition == null:
			return null
		var amount := rng.randi_range(entry.count_min, entry.count_max)
		if amount <= 0:
			return null
		var quality := minf(100.0, rng.randf_range(entry.quality_min, entry.quality_max) + luck * 10.0)
		return ItemStack.new(definition, amount, quality)
	return null


# ---------------------------------------------------------------------------
# Yenilenme
# ---------------------------------------------------------------------------
func restock_tokens(building_id: String, day: int) -> int:
	var clock: Dictionary = building_clock.get(building_id, {})
	if clock.is_empty():
		return 0
	var every := maxi(1, int(rules().get("restock_days", 6)))
	var earned := maxi(0, (day - int(clock.t0)) / every)
	return clampi(earned - int(clock.used), 0, int(rules().get("restock_max_tokens", 2)))


func can_restock(plan: Dictionary, f: Dictionary, day: int) -> bool:
	return status(f) == "empty" and restock_tokens(plan.id, day) > 0


func restock(plan: Dictionary, f: Dictionary, day: int, luck: float = 0.0) -> bool:
	## Bos container'da YENI arama tamamlandi: jeton harca, azaltilmis zar at.
	if not can_restock(plan, f, day):
		return false
	var clock: Dictionary = building_clock[plan.id]
	var every := maxi(1, int(rules().get("restock_days", 6)))
	var earned := maxi(0, (day - int(clock.t0)) / every)
	var cap := int(rules().get("restock_max_tokens", 2))
	# Tavan: birikmesine izin verilmeyen jetonlar yanar (sonsuz birikim yok).
	clock.used = maxi(int(clock.used), earned - cap) + 1
	var s := _state_mut(f.id)
	s.n = int(s.n) + 1
	var base: int = allocation(plan).get(f.id, 0)
	var rolls := maxi(1, roundi(maxf(1.0, float(base)) * float(rules().get("restock_share", 0.5))))
	s.items = _roll_items(f, rolls, hash("%s:%d" % [f.id, s.n]), luck, false)
	s.day = day
	s.p = 0.0
	return true


# ---------------------------------------------------------------------------
# Arama ilerlemesi, alma, tahrip
# ---------------------------------------------------------------------------
func progress(id: String) -> float:
	return float(state(id).get("p", 0.0))


func set_progress(id: String, value: float) -> void:
	_state_mut(id).p = clampf(value, 0.0, 1.0)


func set_open(id: String, open: bool) -> void:
	_state_mut(id).o = open


func take(id: String, index: int, count: int, inventory: Inventory) -> Dictionary:
	## Tek yigindan `count` adet (<= 0: hepsi). Sigmayan kisim container'da kalir.
	var s := state(id)
	if s.is_empty() or index < 0 or index >= s.items.size():
		return {"taken": 0}
	var stack: ItemStack = s.items[index]
	var wanted := stack.quantity if count <= 0 else mini(count, stack.quantity)
	var moving := stack.copy(wanted)
	var left := inventory.add(moving)
	var taken := wanted - left
	stack.quantity -= taken
	if stack.quantity <= 0:
		s.items.remove_at(index)
	return {"taken": taken, "stack": stack.copy(taken) if taken > 0 else null}


func take_all(id: String, inventory: Inventory) -> Dictionary:
	## Kapasite yettigince hepsini al; sigmayan esya container'da KALIR.
	var taken: Array = []
	var s := state(id)
	if s.is_empty():
		return {"taken": taken}
	for i in range(s.items.size() - 1, -1, -1):
		var result := take(id, i, 0, inventory)
		if result.taken > 0:
			taken.append(result.stack)
	return {"taken": taken}


func destroy(plan: Dictionary, f: Dictionary, day: int) -> Array:
	## Container kirildi: kalan icerik BIR KEZ doner (enkaz yigini). Hic
	## aranmadiysa zar simdi atilir ve bir kismi kirilmada heba olur.
	var s := _state_mut(f.id)
	if s.d:
		return []
	if not s.r:
		roll(plan, f, day)
		var keep := float(rules().get("destroy_keep", 0.6))
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(f.id + ":kirik")
		var kept: Array = []
		for stack: ItemStack in s.items:
			var n := roundi(stack.quantity * keep)
			if n <= 0 and rng.randf() < keep:
				n = 1
			if n > 0:
				kept.append(stack.copy(n))
		s.items = kept
	s.d = true
	var remaining: Array = s.items
	s.items = []
	return remaining


# ---------------------------------------------------------------------------
# Kayit
# ---------------------------------------------------------------------------
func to_dict() -> Dictionary:
	var out := {}
	for id: String in states:
		var s: Dictionary = states[id]
		var stacks: Array = []
		for stack: ItemStack in s.items:
			stacks.append(stack.to_dict())
		out[id] = {"r": s.r, "i": stacks, "p": snappedf(float(s.p), 0.01), "o": s.o, "d": s.d, "n": s.n, "day": s.day}
		if s.get("u", false):
			out[id]["u"] = true
	return {"states": out, "clock": building_clock.duplicate(true), "migrated_buildings": migrated.duplicate()}


func load_dict(data: Dictionary) -> void:
	states.clear()
	building_clock.clear()
	for id: String in data.get("states", {}):
		var raw: Dictionary = data.states[id]
		var stacks: Array = []
		for s: Variant in raw.get("i", []):
			if typeof(s) == TYPE_DICTIONARY:
				var stack := ItemStack.from_dict(s, Content.items)
				if stack != null:
					stacks.append(stack)
		states[id] = {"r": bool(raw.get("r", false)), "items": stacks, "p": float(raw.get("p", 0.0)),
			"o": bool(raw.get("o", false)), "d": bool(raw.get("d", false)), "n": int(raw.get("n", 0)),
			"day": int(raw.get("day", 0)), "u": bool(raw.get("u", false))}
	for bid: String in data.get("clock", {}):
		var c: Dictionary = data.clock[bid]
		building_clock[bid] = {"t0": int(c.get("t0", 0)), "used": int(c.get("used", 0))}
	migrated = data.get("migrated_buildings", {}).duplicate()


func migrate_v1(old_states: Dictionary, day: int) -> Dictionary:
	## Eski (v1) bina arama haklari -> container durumu. Kural: binanin
	## kullanilmis hak orani kadar container'i "aranmis ve bos" isaretle
	## (deterministik sira); yenilenme saati eski son arama gununden baslar.
	## Tam yagmalanmis bina ikinci kez tam dolu odul VERMEZ.
	## Donus: {binalar, bosaltilan container, planı olmayan bina}.
	var report := {"buildings": 0, "emptied": 0, "no_interior": 0}
	if _building_index.is_empty():
		for i in city.buildings.size():
			_building_index[city.buildings[i].id] = i
	for bid: String in old_states:
		var old: Dictionary = old_states[bid]
		var searched := int(old.get("searched", 0))
		if searched <= 0 or not _building_index.has(bid):
			continue
		var index: int = _building_index[bid]
		var plan := city.interior_plan(index)
		report.buildings += 1
		var last_day := int(old.get("last_day", day))
		# Eski kisi yenilenme: her 6 gunde bir hak geri gelirdi.
		var restored := maxi(0, (day - last_day) / 6)
		var used := maxi(0, searched - restored)
		building_clock[bid] = {"t0": last_day, "used": 0}
		if not plan.get("ok", false):
			report.no_interior += 1
			continue
		var cls := Content.building_class(str(plan["class"]))
		var fraction := clampf(float(used) / maxf(1.0, float(cls.max_searches)), 0.0, 1.0)
		var ids: Array = []
		for f: Dictionary in plan.furniture:
			if f.container != "":
				ids.append(f.id)
		ids.sort()
		var count := ceili(fraction * ids.size())
		for i in count:
			var s := _state_mut(ids[i])
			s.r = true
			s.items = []
			s.day = last_day
			report.emptied += 1
	return report
