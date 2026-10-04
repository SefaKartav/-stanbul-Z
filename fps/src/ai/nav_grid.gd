class_name NavGrid
extends RefCounted
## Zombi yol bulma: voxel dunyasindan turetilen 2.5B yurunebilirlik +
## oyuncuya dogru AKIS ALANI (Python: engine/pathfinding.py).
##
## NEDEN AJAN BASINA A* DEGIL?
##   Tek bir mesafe haritasi (hedeften geriye Dijkstra) ile yuzlerce zombi
##   kendi hucresindeki hazir yonu okur. Maliyet ajan sayisindan bagimsizdir.
##
## DINAMIK DUNYA
##   Her sutunun "zemin" yuksekligi voxel verisinden okunur ve onbellege
##   alinir; blok degisince yalnizca o sutun gecersiz kilinir. Duvari kirip
##   actigin gecit bir sonraki taramada AI rotasina girer. Tam dunya
##   navmesh'i her mermide yeniden uretilmez.
##
## BARIKAT = MALIYET, DUVAR DEGIL
##   Oyuncunun koydugu zombi-kirilabilir bloklar (tahta, kum torbasi, celik)
##   gecilmez degildir; hucre maliyetini yukseltir. Horde boylece ACIK
##   biraktigin koridora yonelir; baska yol yoksa barikata saldirir.
##   Haritanin kendi duvarlari ise gecilmezdir ve zombiler onlari kazmaz.

const WINDOW := 96                  # alan penceresi (hucre)
const NONE := -100000
const STRAIGHT := 10
const DIAGONAL := 14
const CLIMB := 6
const BARRICADE_COST := 240          # eski oyunda path_cost 24 karo
const MAX_COST := 20000
const OFFSETS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]

var world: VoxelWorld
var ground_hint: Callable          # (x, z) -> int: beklenen zemin (ilk bos hucre)
var _floor_cache: Dictionary = {}  # Vector2i -> [zemin_y, barikat_mi]

# Hazir alan (okunan) ve yapilmakta olan alan (yazilan) ayridir: tarama
# birkac kareye yayilirken zombiler eski ama TUTARLI alani okur.
var ready_origin := Vector2i.ZERO
var ready_dist := PackedInt32Array()
var ready_target := Vector2i(1 << 20, 0)
var _work_origin := Vector2i.ZERO
var _work_dist := PackedInt32Array()
var _work_floor := PackedInt32Array()
var _buckets: Dictionary = {}
var _bucket_min := 0
var _building := false
var _target := Vector2i.ZERO
var rebuilds := 0


func _init(p_world: VoxelWorld, p_ground_hint: Callable) -> void:
	world = p_world
	ground_hint = p_ground_hint
	world.block_changed.connect(_on_block_changed)


func _on_block_changed(cell: Vector3i, _previous: int, _current: int) -> void:
	_floor_cache.erase(Vector2i(cell.x, cell.z))


func clear_cache() -> void:
	_floor_cache.clear()


# --- sutun analizi ---
func column(x: int, z: int) -> Array:
	## [zemin_y, barikat]: zemin_y = ayakta durulan hucrenin y'si (NONE: yok).
	var key := Vector2i(x, z)
	var cached: Variant = _floor_cache.get(key)
	if cached != null:
		return cached
	var result := _scan(x, z)
	_floor_cache[key] = result
	return result


func _scan(x: int, z: int) -> Array:
	var base: int = ground_hint.call(x, z)
	var barricade := false
	# ASAGIDAN YUKARI: sokak seviyesindeki ilk zemin alinir. Yukaridan
	# taransa 2 m'lik barikatin USTU zemin sayilir ve barikat hic gorulmezdi.
	for y in range(base - 4, base + 3):
		var below := world.get_block(x, y - 1, z)
		if not _supports(below):
			continue
		var a := world.get_block(x, y, z)
		var b := world.get_block(x, y + 1, z)
		var a_ok := _clear(a)
		var b_ok := _clear(b)
		if a_ok and b_ok:
			return [y, false]
		# Oyuncu barikati: gecilemez ama saldirilabilir hucre.
		if (a_ok or _breakable_placed(x, y, z, a)) and (b_ok or _breakable_placed(x, y + 1, z, b)):
			barricade = true
			return [y, barricade]
	return [NONE, false]


func _supports(value: int) -> bool:
	return value == VoxelWorld.BOUNDARY or (value != 0 and world.materials.solid[value] == 1)


func _clear(value: int) -> bool:
	if value == VoxelWorld.BOUNDARY:
		return false
	if value != 0 and world.materials.liquid[value] == 1:
		return false                 # zombiler denizden/sudan yurumez
	return value == 0 or world.materials.solid[value] == 0 \
		or world.materials.shape[value] == BlockMaterials.SHAPE_SLAB


func _breakable_placed(x: int, y: int, z: int, value: int) -> bool:
	return value != 0 and value != VoxelWorld.BOUNDARY \
		and world.materials.zombie_breakable[value] == 1 and world.placed.has(Vector3i(x, y, z))


func barricade_cell(x: int, z: int) -> Vector3i:
	## Sutundaki saldirilacak barikat hucresi (yoksa y = NONE).
	var info := column(x, z)
	if info[0] == NONE or not info[1]:
		return Vector3i(x, NONE, z)
	for y in [info[0], info[0] + 1]:
		var value := world.get_block(x, y, z)
		if _breakable_placed(x, y, z, value):
			return Vector3i(x, y, z)
	return Vector3i(x, NONE, z)


# --- akis alani ---
func begin(target: Vector2i) -> void:
	_target = target
	_work_origin = target - Vector2i(WINDOW / 2, WINDOW / 2)
	_work_dist = PackedInt32Array()
	_work_dist.resize(WINDOW * WINDOW)
	_work_dist.fill(MAX_COST)
	_work_floor = PackedInt32Array()
	_work_floor.resize(WINDOW * WINDOW)
	_work_floor.fill(NONE - 1)      # henuz okunmadi
	_buckets = {}
	_bucket_min = 0
	var start := _local(target)
	if _floor_of(start.x, start.y) == NONE:
		# Hedef kati bir yerdeyse (merdiven, arac ustu) en yakin zemine dus.
		var found := false
		for r in range(1, 4):
			for dz in range(-r, r + 1):
				for dx in range(-r, r + 1):
					if not found and _floor_of(start.x + dx, start.y + dz) != NONE:
						start = Vector2i(start.x + dx, start.y + dz)
						found = true
		if not found:
			_building = false
			return
	_work_dist[start.y * WINDOW + start.x] = 0
	_push(0, start.y * WINDOW + start.x)
	_building = true


func step(budget_usec: int) -> bool:
	## Taramayi ilerletir. Bittiyse hazir alani degistirir ve true doner.
	if not _building:
		return true
	var started := Time.get_ticks_usec()
	var processed := 0
	while true:
		var index := _pop()
		if index < 0:
			_finish()
			return true
		var cost := _work_dist[index]
		var lx := index % WINDOW
		var lz := index / WINDOW
		var here := _floor_of(lx, lz)
		for k in 8:
			var o: Vector2i = OFFSETS[k]
			var nx := lx + o.x
			var nz := lz + o.y
			if nx < 0 or nz < 0 or nx >= WINDOW or nz >= WINDOW:
				continue
			var there := _floor_of(nx, nz)
			if there == NONE or absi(there - here) > 1:
				continue
			if k >= 4:
				# Kose kesme yok: iki dik komsu da gecilebilir olmali.
				var a := _floor_of(lx + o.x, lz)
				var b := _floor_of(lx, lz + o.y)
				if a == NONE or b == NONE or absi(a - here) > 1 or absi(b - here) > 1:
					continue
			var step_cost := DIAGONAL if k >= 4 else STRAIGHT
			if there != here:
				step_cost += CLIMB
			if _is_barricade(nx, nz):
				step_cost += BARRICADE_COST
			var next_cost := cost + step_cost
			var n_index := nz * WINDOW + nx
			if next_cost < _work_dist[n_index]:
				_work_dist[n_index] = next_cost
				_push(next_cost, n_index)
		processed += 1
		if processed % 64 == 0 and Time.get_ticks_usec() - started > budget_usec:
			return false
	return true


func _finish() -> void:
	ready_dist = _work_dist
	ready_origin = _work_origin
	ready_target = _target
	_building = false
	rebuilds += 1


func building() -> bool:
	return _building


func _local(cell: Vector2i) -> Vector2i:
	return cell - _work_origin


func _floor_of(lx: int, lz: int) -> int:
	if lx < 0 or lz < 0 or lx >= WINDOW or lz >= WINDOW:
		return NONE
	var i := lz * WINDOW + lx
	var value := _work_floor[i]
	if value == NONE - 1:
		value = column(_work_origin.x + lx, _work_origin.y + lz)[0]
		_work_floor[i] = value
	return value


func _is_barricade(lx: int, lz: int) -> bool:
	return column(_work_origin.x + lx, _work_origin.y + lz)[1]


func _push(cost: int, index: int) -> void:
	# Array (referans tipi) bilincli: Packed dizi deger tipidir ve her
	# cekiste kopyalanirdi.
	var bucket: Array = _buckets.get(cost, [])
	if bucket.is_empty():
		_buckets[cost] = bucket
	bucket.append(index)
	if cost < _bucket_min:
		_bucket_min = cost


func _pop() -> int:
	## Dial'in kova kuyrugu: tamsayi maliyetlerde yiginsiz Dijkstra.
	while _bucket_min <= MAX_COST:
		if _buckets.has(_bucket_min):
			var bucket: Array = _buckets[_bucket_min]
			while not bucket.is_empty():
				var index: int = bucket.pop_back()
				if _work_dist[index] == _bucket_min:
					return index
			_buckets.erase(_bucket_min)
		_bucket_min += 1
		if _buckets.is_empty():
			return -1
	return -1


# --- sorgu ---
func distance_at(x: int, z: int) -> int:
	var l := Vector2i(x, z) - ready_origin
	if ready_dist.is_empty() or l.x < 0 or l.y < 0 or l.x >= WINDOW or l.y >= WINDOW:
		return -1
	var d := ready_dist[l.y * WINDOW + l.x]
	return -1 if d >= MAX_COST else d


func next_step(x: int, z: int) -> Dictionary:
	## Bu hucreden hedefe dogru bir sonraki hucre: {cell, floor, barricade}
	## ya da bos sozluk (alan disi / ulasilamaz).
	var here := distance_at(x, z)
	if here < 0:
		return {}
	var best := here
	var best_cell := Vector2i(x, z)
	for o: Vector2i in OFFSETS:
		var d := distance_at(x + o.x, z + o.y)
		if d >= 0 and d < best:
			best = d
			best_cell = Vector2i(x + o.x, z + o.y)
	if best_cell == Vector2i(x, z):
		return {}
	var info := column(best_cell.x, best_cell.y)
	return {"cell": best_cell, "floor": info[0], "barricade": info[1]}


func reachable(x: int, z: int) -> bool:
	return distance_at(x, z) >= 0
