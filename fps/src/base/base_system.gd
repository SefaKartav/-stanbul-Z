class_name BaseSystem
extends Node
## Us yonetimi: kurma, kapalilik izleme, bina rolleri, revir, gunluk
## tuketim (Python: systems/settlements.py + gameplay._consume_daily_resources).
##
## KAPALILIK HER KARE OLCULMEZ: yalnizca oyuncunun blok koydugu/kirdigi ya
## da barikat yikildigi zaman ve ancak us chunk'lari yukluyken yeniden
## olculur. Barikat yikilinca us SILINMEZ; "acik" isaretlenir ve oyuncu
## uyarilir ("icerideyim, guvendeyim" sanip olmesin).

signal founded(base: Settlement)
signal breached(base: Settlement)
signal restored(base: Settlement)
signal message(text: String, color: Color)

const RECHECK_INTERVAL := 0.75
const INFIRMARY_WARMUP := 2.0

var world: VoxelWorld
var nav: NavGrid
var registry: BuildingRegistry
var colony: Colony
var settlements: Array = []
var next_id := 1
var last_result: Dictionary = {}
var inside: Settlement = null
var healing_enabled := true
var shortages := {}               # tum usler: kaynak -> true
var _dirty := false
var _timer := 0.0
var _infirmary_time := 0.0


func setup(p_world: VoxelWorld, p_nav: NavGrid, p_registry: BuildingRegistry) -> void:
	world = p_world
	nav = p_nav
	registry = p_registry
	colony = Colony.new(settlements)
	world.block_changed.connect(_on_block_changed)


func _on_block_changed(cell: Vector3i, previous: int, current: int) -> void:
	# Yalnizca oyuncu bloklari kapaliligi etkiler (haritanin kendi duvari
	# kirilirsa da bir gecit acilabilir: onu da say).
	if settlements.is_empty():
		return
	for base: Settlement in settlements:
		if Vector2(cell.x, cell.z).distance_to(Vector2(base.seed_cell)) < Settlement.MAX_RADIUS + 4:
			_dirty = true
			return


func settlement_at(position: Vector3) -> Settlement:
	for base: Settlement in settlements:
		if base.contains_position(position):
			return base
	return null


func try_found(position: Vector3, day: int) -> Dictionary:
	var seed := Vector2i(floori(position.x), floori(position.z))
	if settlement_at(position) != null:
		last_result = {"enclosed": false, "reason": "Burada zaten bir us var", "leaks": []}
		return last_result
	var result := Settlement.evaluate(nav, world, seed)
	last_result = result
	if not result.enclosed:
		return result
	var base := Settlement.new()
	base.id = "base%d" % next_id
	base.name = "Us %d" % next_id
	next_id += 1
	base.seed_cell = seed
	base.seed_y = int(result.interior.get(seed, 0))
	base.interior = result.interior
	base.day_founded = day
	settlements.append(base)
	refresh_buildings(base)
	colony.sync_population()
	founded.emit(base)
	return result


func abandon(base: Settlement) -> void:
	settlements.erase(base)
	colony.sync_population()


# --- bina rolleri ---
func adjacent_buildings(base: Settlement) -> Array:
	## Ic alana bitisik binalar (rol atanabilir). Bina ICINE GIRILMEZ;
	## rol bir kapasite dugumudur.
	var found := {}
	if registry == null:
		return []
	for cell: Vector2i in base.interior:
		for o: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var index := registry.generator.building_at(cell.x + o.x, cell.y + o.y)
			if index >= 0:
				found[index] = true
	return found.keys()


func refresh_buildings(base: Settlement) -> void:
	## Alan olcegi haritadan turetilir; kayit dosyasina kopyalanmaz.
	base.building_scales = {}
	for index: int in adjacent_buildings(base):
		var b := registry.get_building(index)
		# Eski: alan_karo / 24 (1 karo = 4 m2) -> m2 / 96, 0.5..3.0
		base.building_scales[b.id] = clampf(registry.area_m2(index) / 96.0, 0.5, 3.0)
	base.apply_storage_capacity()


func assign_role(base: Settlement, building_id: String, role: String) -> void:
	base.assign(building_id, role)
	base.apply_storage_capacity()


# --- dongu ---
func physics_step(delta: float, player_position: Vector3, vitals: PlayerVitals) -> void:
	_timer -= delta
	if _dirty and _timer <= 0.0:
		_timer = RECHECK_INTERVAL
		_dirty = false
		_recheck(player_position)
	var previous := inside
	inside = settlement_at(player_position)
	if inside != previous:
		_infirmary_time = 0.0
		if inside != null:
			message.emit("%s -- ussun icindesin%s" % [inside.name, " (ACIK!)" if inside.breached else ""],
				Hud.RED if inside.breached else Hud.GREEN)
	if inside != null:
		_tick_infirmary(inside, delta, vitals)


func _recheck(player_position: Vector3) -> void:
	for base: Settlement in settlements:
		# Yuklu olmayan usun kapaliligi olculmez: bilinmeyen hucre duvar
		# sayilirdi ve uzak us yanlislikla "kapali" gorunurdu.
		var chunk := VoxelWorld.chunk_of(Vector3i(base.seed_cell.x, base.seed_y, base.seed_cell.y))
		if not world.has_chunk(chunk):
			continue
		var result := Settlement.evaluate(nav, world, base.seed_cell)
		if result.enclosed:
			base.interior = result.interior
			if base.breached:
				base.breached = false
				restored.emit(base)
			refresh_buildings(base)
			continue
		if base.interior.is_empty() or result.interior.size() > base.interior.size():
			base.interior = result.interior
		if not base.breached:
			base.breached = true
			last_result = result
			breached.emit(base)


func _tick_infirmary(base: Settlement, delta: float, vitals: PlayerVitals) -> void:
	if not healing_enabled or not base.has_role("infirmary"):
		return
	_infirmary_time += delta
	if _infirmary_time < INFIRMARY_WARMUP or vitals.dead or vitals.health >= PlayerVitals.MAX_HEALTH:
		return
	vitals.heal(base.capacity("infirmary") * delta * colony.colony_skills.multiplier("infirmary_heal"))


func consume_daily(day: int) -> Array:
	## Gun donumunde her ussun tuketimi. Kitlik OLDURUCU DEGIL KISITLAYICI.
	## Mesaj listesi dondurur.
	var messages: Array = []
	shortages = {}
	var by_base := {}
	for base: Settlement in settlements:
		by_base[base.id] = {}
		var structures := base.roles.size()
		for resource: Dictionary in Content.resources.resources.values():
			var need := Content.resources.daily_draw(resource, base.population, structures)
			if need <= 0.0:
				continue
			var result := Content.resources.consume(base.stockpile, resource, need)
			if not result[1]:
				by_base[base.id][resource.id] = true
				shortages[resource.id] = true
				messages.append([resource.shortage if resource.shortage != "" else "%s bitti" % resource.name, Hud.RED])
	colony.advance_day(day, by_base)
	for event: String in colony.day_events:
		messages.append([event, Hud.ACCENT])
	for exp: Dictionary in colony.expeditions:
		if exp.status == "completed" and not exp.reported:
			exp.reported = true
			messages.append([exp.report, Hud.GREEN])
	healing_enabled = not shortages.has("water")
	return messages


func respawn_base() -> Settlement:
	## Uyanilacak us: delinmemis olanlarin ilki. Yoksa null (oyun biter).
	for base: Settlement in settlements:
		if not base.breached:
			return base
	return null


func to_dict() -> Dictionary:
	return {"next_id": next_id, "bases": settlements.map(func(b: Settlement) -> Dictionary: return b.to_dict()),
		"colony": colony.to_dict()}


func load_dict(data: Dictionary, day: int) -> void:
	settlements.clear()
	next_id = int(data.get("next_id", 1))
	for raw: Variant in data.get("bases", []):
		if typeof(raw) == TYPE_DICTIONARY:
			var base := Settlement.from_dict(raw)
			settlements.append(base)
	colony.bases = settlements
	colony.load_dict(data.get("colony", {}), day)
	# Ic alan kaydedilmez; chunk'lar yuklenince yeniden olculur.
	_dirty = true
	_timer = 0.0
