class_name InteriorView
extends Node3D
## Yakindaki binalarin ic mekan GORUNUSU, kapilari ve etkilesim hedefi.
##
## Ic mekanin fiziksel gercegi voxel'dir (bkz. CityGenerator + InteriorPlanner):
## duvar, doseme, merdiven gorunur bloklar; mobilya ve kapilar GORUNMEZ katı
## hucrelerdir (carpisma, mermi, gorus ve yol bulma ayni veriyi okur). Bu
## dugum yalnizca o hucrelerin GORSELINI (GLB modeller) oyuncunun yakininda
## kurar. Butun sehirde binlerce dugum olusmaz: yaricap disi binalar bosaltilir.
##
## KAPILAR
##   Kapi = kapi hucrelerinde katı kapi malzemesi. Acmak hucreleri havaya,
##   kapamak geri kapi malzemesine cevirir: mermi, gorus, carpisma ve zombi
##   yol bulmasi AYNI ANDA guncellenir; durum dunya farki olarak kaydedilir.
##   Kapali kapi silahla kirilabilir -> "kirik" (kaydedilir), bir daha kapanmaz.
##
## YIKILABILIRLIK POLITIKASI
##   Mobilya ve kapilar yalnizca silahla (ve boru bombasiyla) kirilir; kazma,
##   yumruk ya da arac yoktur. Mobilyanin herhangi bir hucresi kirilinca butun
##   mobilya gider; container'in kalan icerigi BIR KEZ enkaz yigini olur.

signal container_destroyed(debris: Array, position: Vector3, label: String)
signal door_broken(position: Vector3)

const RADIUS := 42.0
const UNLOAD := 58.0
const REACH := 2.6
const FURNITURE_RANGE := 24.0    # m: mobilya bundan uzakta cizilmez
const DOOR_RANGE := 45.0         # m: kapilar sokaktan gorunur
const LOADS_PER_TICK := 2
## Cok katli binada mobilya yalnizca oyuncunun bulundugu yukseklik bandinda
## (+-7 m: bulundugu kat, bir alti, bir ustu) kurulur. 19 katli binanin
## 500 modeli sokaktan cizilmez; oyuncu merdivenden cikarken bant kayar.
const FLOOR_BAND := 7.0
const DOOR_MATERIALS := ["door_wood", "door_metal", "door_glass"]
const FURNITURE_MATERIALS := ["furniture_wood", "furniture_metal"]

var city: CityGenerator
var world: VoxelWorld
var containers: ContainerRegistry
var day_provider: Callable
var broken_doors: Dictionary = {}     # kapi id -> true (kayitli)
var _loaded: Dictionary = {}          # bina indeksi -> {nodes: {id: Node3D}, doors: {id: Node3D}}
var _door_mats := {}
var _furn_mats := {}
var _busy := false                    # kendi set_block cagrilarimiz sirasinda
var _timer := 0.0
var load_usec_max := 0                # olcum: tek bina gorselinin kurulma suresi
var _focus_y := 0.0
var _budget := 0                      # bu turda kurulabilecek model sayisi
const NODES_PER_TICK := 40


func setup(p_city: CityGenerator, p_world: VoxelWorld, p_containers: ContainerRegistry, p_day: Callable) -> void:
	city = p_city
	world = p_world
	containers = p_containers
	day_provider = p_day
	for id: String in DOOR_MATERIALS:
		_door_mats[world.materials.index_of(id)] = id
	for id: String in FURNITURE_MATERIALS:
		_furn_mats[world.materials.index_of(id)] = id
	world.block_changed.connect(_on_block_changed)


func loaded_count() -> int:
	var n := 0
	for entry: Dictionary in _loaded.values():
		n += entry.nodes.size() + entry.doors.size()
	return n


# ---------------------------------------------------------------------------
# Yukleme / bosaltma
# ---------------------------------------------------------------------------
func update(delta: float, focus: Vector3) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.2
	_focus_y = focus.y
	city.poll_plans()
	_budget = NODES_PER_TICK
	for index: int in _loaded.keys():
		_sync_floors(index)
	# Tur basina en fazla LOADS_PER_TICK bina, en yakindan baslayarak: kosarken
	# ayni karede 5-6 binanin ~80 modeli birden kurulunca kare takiliyordu.
	var near := city.buildings_near(focus, RADIUS)
	var pending: Array = []
	for index: int in near:
		if not _loaded.has(index):
			pending.append(index)
	if pending.size() > LOADS_PER_TICK:
		var flat := Vector2(focus.x, focus.z)
		pending.sort_custom(func(a: int, b: int) -> bool:
			return _building_distance(a, flat) < _building_distance(b, flat))
	for i in mini(LOADS_PER_TICK, pending.size()):
		var started := Time.get_ticks_usec()
		_load_building(pending[i])
		load_usec_max = maxi(load_usec_max, Time.get_ticks_usec() - started)
	var keep := {}
	for index: int in city.buildings_near(focus, UNLOAD):
		keep[index] = true
	for index: int in _loaded.keys():
		if not keep.has(index):
			_unload_building(index)


func _building_distance(index: int, p: Vector2) -> float:
	var b: Dictionary = city.buildings[index]
	return p.clamp(b.lo, b.hi).distance_to(p)


func refresh_all() -> void:
	## Kayit yuklendikten sonra: gorseller dunya durumundan yeniden kurulur.
	for index: int in _loaded.keys():
		_unload_building(index)


func _load_building(index: int) -> void:
	if not city.plan_cached(index):
		city.request_plan(index)       # hazir olunca sonraki turda kurulur
		return
	var plan := city.interior_plan(index)
	if not plan.get("ok", false):
		return
	var door0: Dictionary = plan.doors[0]
	var probe := Vector3i(door0.cell.x, int(plan.floors[0].y), door0.cell.y)
	if not world.has_chunk(VoxelWorld.chunk_of(probe)):
		return            # chunk henuz uretilmedi: sonraki turda dene
	var entry := {"nodes": {}, "doors": {}, "floors": {}}
	_loaded[index] = entry
	_sync_floors(index)
	for door: Dictionary in plan.doors:
		_build_door(plan, door, entry)


func _wanted_floors(plan: Dictionary) -> Dictionary:
	var wanted := {}
	for k in plan.floors.size():
		if absf(float(plan.floors[k].y) + 1.5 - _focus_y) <= FLOOR_BAND:
			wanted[k] = true
	return wanted


func _sync_floors(index: int) -> void:
	## Yukseklik bandina giren katlarin mobilyasini kur, cikanlarinkini birak.
	var entry: Dictionary = _loaded.get(index, {})
	if entry.is_empty():
		return
	var plan := city.interior_plan(index)
	var wanted := _wanted_floors(plan)
	for k in plan.floors.size():
		if not wanted.has(k) and not entry.nodes.is_empty():
			for f: Dictionary in plan.floors[k].furniture:
				var node: Node3D = entry.nodes.get(f.id)
				if node != null and is_instance_valid(node):
					node.queue_free()
				entry.nodes.erase(f.id)
			entry.floors.erase(k)
	for k: int in wanted:
		if entry.floors.has(k):
			continue
		var complete := true
		for f: Dictionary in plan.floors[k].furniture:
			if entry.nodes.has(f.id):
				continue
			if _budget <= 0:
				complete = false        # kalan modeller sonraki turda (takilma yok)
				break
			if _furniture_gone(plan, f):
				continue
			_budget -= 1
			var node := AssetLibrary.instantiate(f.asset)
			node.position = f.origin
			node.rotation.y = f.yaw
			_no_shadows(node)
			add_child(node)
			if f.container != "" and bool(containers.state(f.id).get("o", false)):
				AssetLibrary.pose_open(node, f.asset, 1.0)
			entry.nodes[f.id] = node
		if complete:
			entry.floors[k] = true


func _unload_building(index: int) -> void:
	var entry: Dictionary = _loaded.get(index, {})
	for node: Node3D in entry.get("nodes", {}).values():
		if is_instance_valid(node):
			node.queue_free()
	for node: Node3D in entry.get("doors", {}).values():
		if is_instance_valid(node):
			node.queue_free()
	_loaded.erase(index)


func _build_door(plan: Dictionary, door: Dictionary, entry: Dictionary) -> void:
	if entry.doors.has(door.id):
		entry.doors[door.id].queue_free()
		entry.doors.erase(door.id)
	var state := door_state(plan, door)
	if state == "broken":
		return
	var node := AssetLibrary.instantiate(door.asset)
	var out: Vector2i = door.outward
	node.position = Vector3(door.cell.x + 0.5, float(plan.floors[0].y), door.cell.y + 0.5)
	node.rotation.y = atan2(-float(out.x), -float(out.y))
	if int(door.get("rows", 2)) == 3:
		node.scale.y = 3.0 / 2.2       # esigi yuksek girislerde 3 m acilik
	_no_shadows(node, DOOR_RANGE)
	add_child(node)
	if state == "open":
		AssetLibrary.pose_open(node, door.asset, 1.0)
	entry.doors[door.id] = node


func _furniture_gone(plan: Dictionary, f: Dictionary) -> bool:
	if f.container != "" and bool(containers.state(f.id).get("d", false)):
		return true
	if not f.solid:
		return false
	var cell: Vector2i = f.cells[0]
	var y := int(plan.floors[f.floor].y) + int(f.rows[0])
	return world.get_visual_block(cell.x, y, cell.y) == 0


static func _no_shadows(node: Node, visible_range: float = FURNITURE_RANGE) -> void:
	## Ic mekan mobilyasi golge dusurmez: odalar zaten kapali, yuzlerce model
	## golge haritasina girerse maliyet buyurdu. Ayrica gorunurluk mesafesi:
	## mobilya ancak iceriden ya da pencereden yakindan gorulur; 42 m
	## yaricaptaki ~300 model her karede cizilince bosta FPS 176 -> 160 dustu.
	if node is GeometryInstance3D:
		var geometry := node as GeometryInstance3D
		geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		geometry.visibility_range_end = visible_range
	for child in node.get_children():
		_no_shadows(child, visible_range)


# ---------------------------------------------------------------------------
# Kapilar
# ---------------------------------------------------------------------------
func door_state(plan: Dictionary, door: Dictionary) -> String:
	if broken_doors.has(door.id):
		return "broken"
	var value := world.get_visual_block(door.cell.x, int(plan.floors[0].y), door.cell.y)
	return "closed" if _door_mats.has(value) else "open"


func toggle_door(plan: Dictionary, door: Dictionary, occupied: Callable) -> String:
	## Ac/kapa. `occupied(aabb_min, aabb_max) -> bool`: kapi hucresinde govde var mi?
	var state := door_state(plan, door)
	if state == "broken":
		return "Kapi kirik"
	var y0 := int(plan.floors[0].y)
	var rows := int(door.get("rows", 2))
	var material := 0
	if state == "open":
		var lo := Vector3(door.cell.x, y0, door.cell.y)
		if occupied.is_valid() and occupied.call(lo, lo + Vector3(1, rows, 1)):
			return "Kapinin onu dolu"
		material = world.materials.index_of(door.material)
	_busy = true
	for r in rows:
		world.set_block(Vector3i(door.cell.x, y0 + r, door.cell.y), material, VoxelWorld.ORIGIN_WORLD)
	_busy = false
	var entry: Dictionary = _loaded.get(int(plan.index), {})
	if not entry.is_empty():
		_build_door(plan, door, entry)
	return "Kapi kapandi" if material != 0 else "Kapi acildi"


# ---------------------------------------------------------------------------
# Container gorseli
# ---------------------------------------------------------------------------
func set_container_open(plan: Dictionary, f: Dictionary, open: bool) -> void:
	containers.set_open(f.id, open)
	var entry: Dictionary = _loaded.get(int(plan.index), {})
	var node: Node3D = entry.get("nodes", {}).get(f.id)
	if node != null and is_instance_valid(node):
		AssetLibrary.pose_open(node, f.asset, 1.0 if open else 0.0)


# ---------------------------------------------------------------------------
# Tahrip
# ---------------------------------------------------------------------------
func _on_block_changed(cell: Vector3i, previous: int, current: int) -> void:
	if _busy or current != 0:
		return
	if _door_mats.has(previous):
		var hit := city.door_at(Vector2i(cell.x, cell.z))
		if hit.is_empty():
			return
		var door: Dictionary = hit.door
		broken_doors[door.id] = true
		_busy = true
		for r in int(door.get("rows", 2)):
			world.set_block(Vector3i(door.cell.x, int(hit.plan.floors[0].y) + r, door.cell.y), 0, VoxelWorld.ORIGIN_WORLD)
		_busy = false
		var entry: Dictionary = _loaded.get(int(hit.plan.index), {})
		if not entry.is_empty():
			_build_door(hit.plan, door, entry)
		door_broken.emit(Vector3(cell) + Vector3(0.5, 0.5, 0.5))
	elif _furn_mats.has(previous):
		var fa := city.furniture_at(cell)
		if fa.is_empty():
			return
		_destroy_furniture(fa.plan, fa.f)


func _destroy_furniture(plan: Dictionary, f: Dictionary) -> void:
	var y0 := int(plan.floors[f.floor].y)
	_busy = true
	for c: Vector2i in f.cells:
		for r in range(int(f.rows[0]), int(f.rows[1]) + 1):
			var cell := Vector3i(c.x, y0 + r, c.y)
			if _furn_mats.has(world.get_block(cell.x, cell.y, cell.z)):
				world.set_block(cell, 0, VoxelWorld.ORIGIN_WORLD)
	_busy = false
	var entry: Dictionary = _loaded.get(int(plan.index), {})
	var node: Node3D = entry.get("nodes", {}).get(f.id)
	if node != null and is_instance_valid(node):
		node.queue_free()
		entry.nodes.erase(f.id)
	if f.container != "":
		var day: int = day_provider.call() if day_provider.is_valid() else 1
		var debris := containers.destroy(plan, f, day)
		var label := str(ContainerRegistry.type_def(f.container).get("label", "Dolap"))
		container_destroyed.emit(debris, Vector3(f.origin.x, y0 + 0.3, f.origin.z), "Enkaz: " + label)


# ---------------------------------------------------------------------------
# Etkilesim hedefi
# ---------------------------------------------------------------------------
func find_target(eye: Vector3, look: Vector3, feet: Vector3) -> Dictionary:
	## Bakilan, menzildeki, ENGELSIZ fiziksel nesne. Duvar, kat, kapali kapi ya
	## da cam arkasindaki dolap hedeflenemez: isin ilk katı hucrede durur.
	var hit := VoxelRay.cast(world, eye, look, REACH)
	if not hit.is_empty() and not hit.boundary:
		var value: int = hit.value
		var cell: Vector3i = hit.cell
		if _door_mats.has(value):
			var d := city.door_at(Vector2i(cell.x, cell.z))
			if not d.is_empty():
				return {"kind": "door", "plan": d.plan, "door": d.door, "state": "closed"}
		if _furn_mats.has(value):
			var fa := city.furniture_at(cell)
			if not fa.is_empty() and fa.f.container != "":
				var inside := city.building_at(floori(feet.x), floori(feet.z)) == int(fa.plan.index)
				var on_floor := absf(feet.y - float(fa.plan.floors[fa.f.floor].y)) < 1.2
				if not inside or not on_floor:
					return {"kind": "blocked", "reason": "Iceri girmeden aranamaz"}
				return {"kind": "container", "plan": fa.plan, "f": fa.f}
		if hit.distance < REACH - 0.2:
			return {}
	# Acik kapi: isin bosluktan gecer; kapiya yakin ve ona bakiyorsa kapatilabilir.
	for index: int in _loaded:
		var plan := city.interior_plan(index)
		for door: Dictionary in plan.doors:
			var center := Vector3(door.cell.x + 0.5, float(plan.floors[0].y) + 1.0, door.cell.y + 0.5)
			var to := center - eye
			if to.length() > REACH or to.normalized().dot(look) < 0.75:
				continue
			var state := door_state(plan, door)
			if state == "open":
				return {"kind": "door", "plan": plan, "door": door, "state": "open"}
	return {}
