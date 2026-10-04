class_name Settlement
extends RefCounted
## Us = BARIKATLANMIS MAHALLE (Python: game/base/settlement.py).
##
## Us bir bina degil, KAPATILMIS BIR SOKAK PARCASIDIR. Voxel dunyasinda
## binalar zaten dolu hacimdir (dogal duvar); oyuncu sokagin iki ucunu
## barikatla kapatinca kapali alan olusur ve orasi us olarak taninir.
## Barikat yikilinca us SILINMEZ, "acik" (breached) isaretlenir.

const MAX_RADIUS := 48              # hucre (m): tipik bir ada ve sokaklari
const MAX_FLOOD_CELLS := 24000      # eski: 6000 karo x 4 m2
const MIN_AREA := 160               # eski: 40 karo x 4 m2
const MAX_REPORTED_LEAKS := 6

const ROLES := ["none", "storage", "workshop", "dorm", "infirmary", "kitchen"]
const ROLE_LABELS := {"none": "Bos", "storage": "Depo", "workshop": "Atolye", "dorm": "Yatakhane",
	"infirmary": "Revir", "kitchen": "Mutfak"}
# Rol basina temel kapasite; bina alaniyla olceklenir (buyuk depo daha cok alir).
const ROLE_BASE_CAPACITY := {"storage": 120.0, "dorm": 2.0, "infirmary": 1.6, "kitchen": 0.25, "workshop": 1.0}

var id := ""
var name := ""
var seed_cell := Vector2i.ZERO
var seed_y := 0
var interior: Dictionary = {}       # Vector2i -> zemin y
var day_founded := 1
var population := 1
var breached := false
var roles: Dictionary = {}          # bina kimligi -> rol
var building_scales: Dictionary = {}
var stockpile := Inventory.new(120.0, 200)
# Ussun icine yerlestirilmis koloni yapilarinin rol katkisi (yatak -> dorm,
# revir yatagi -> infirmary, mutfak ocagi -> kitchen, zanaat tezgahi ->
# workshop, raf -> storage kg). Game, yerlestirilebilirler degisince yazar.
var extra_capacity: Dictionary = {}


func area() -> int:
	return interior.size()


func contains(cell: Vector2i) -> bool:
	return interior.has(cell)


func contains_position(position: Vector3) -> bool:
	return interior.has(Vector2i(floori(position.x), floori(position.z)))


func centre() -> Vector3:
	if interior.is_empty():
		return Vector3(seed_cell.x + 0.5, seed_y, seed_cell.y + 0.5)
	var sum := Vector2.ZERO
	for cell: Vector2i in interior:
		sum += Vector2(cell)
	var c := sum / interior.size()
	# Merkez bir binanin icine dusebilir: en yakin ic hucreyi don.
	var best := seed_cell
	var best_d := INF
	for cell: Vector2i in interior:
		var d := Vector2(cell).distance_squared_to(c)
		if d < best_d:
			best_d = d
			best = cell
	return Vector3(best.x + 0.5, float(interior[best]), best.y + 0.5)


func role_of(building_id: String) -> String:
	return roles.get(building_id, "none")


func assign(building_id: String, role: String) -> void:
	if role == "none":
		roles.erase(building_id)
	else:
		roles[building_id] = role


func buildings_with(role: String) -> Array:
	var result: Array = []
	for building_id: String in roles:
		if roles[building_id] == role:
			result.append(building_id)
	return result


func capacity(role: String) -> float:
	var total := 0.0
	for building_id: String in buildings_with(role):
		total += float(building_scales.get(building_id, 1.0))
	return float(ROLE_BASE_CAPACITY.get(role, 0.0)) * total + float(extra_capacity.get(role, 0.0))


func has_role(role: String) -> bool:
	## Rol bir binaya atanmis YA DA usteki bir yapi saglıyor.
	return not buildings_with(role).is_empty() or float(extra_capacity.get(role, 0.0)) > 0.0


func apply_storage_capacity() -> void:
	stockpile.capacity_kg = maxf(ROLE_BASE_CAPACITY.storage, capacity("storage"))


static func evaluate(nav: NavGrid, world: VoxelWorld, seed: Vector2i) -> Dictionary:
	## Kapalilik: tohumdan tasma. Oyuncu bloklari (barikat) ve yurunemez
	## sutunlar (binalar) gecilmez. Yaricapin disina tasma = SIZINTI.
	## {enclosed, interior: {cell: y}, leaks: [Vector2i], reason}
	var seed_info := nav.column(seed.x, seed.y)
	if seed_info[0] == NavGrid.NONE or seed_info[1]:
		return {"enclosed": false, "interior": {}, "leaks": [], "reason": "Burada duramazsin"}
	var visited := {seed: seed_info[0]}
	var queue: Array = [seed]
	var head := 0
	var leaks: Array = []
	while head < queue.size():
		if visited.size() > MAX_FLOOD_CELLS:
			return {"enclosed": false, "interior": visited, "leaks": _closest(leaks, seed),
				"reason": "Alan cok genis -- daha dar bir sokak sec"}
		var cell: Vector2i = queue[head]
		head += 1
		var here: int = visited[cell]
		for o: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n := cell + o
			if visited.has(n):
				continue
			var info := nav.column(n.x, n.y)
			# Barikat (oyuncu blogu) ve yurunemez sutun gecilmez.
			if info[0] == NavGrid.NONE or info[1] or absi(int(info[0]) - here) > 1:
				continue
			if _blocked_by_placed(world, n, int(info[0])):
				continue
			if absi(n.x - seed.x) > MAX_RADIUS or absi(n.y - seed.y) > MAX_RADIUS:
				leaks.append(n)
				continue
			visited[n] = info[0]
			queue.append(n)
	if not leaks.is_empty():
		return {"enclosed": false, "interior": visited, "leaks": _closest(leaks, seed),
			"reason": "Cevre kapali degil -- isaretli gecitleri barikatla"}
	if visited.size() < MIN_AREA:
		return {"enclosed": false, "interior": visited, "leaks": [], "reason": "Alan cok kucuk"}
	return {"enclosed": true, "interior": visited, "leaks": [], "reason": ""}


static func _blocked_by_placed(world: VoxelWorld, cell: Vector2i, floor_y: int) -> bool:
	## Zemin ustundeki 2 hucreden biri oyuncu blogu mu? (tuzak/taret degil,
	## yalnizca BLOK barikatlar kapalilik saglar)
	for y in [floor_y, floor_y + 1]:
		if world.placed.has(Vector3i(cell.x, y, cell.y)) and world.get_block(cell.x, y, cell.y) != 0:
			return true
	return false


static func _closest(leaks: Array, origin: Vector2i) -> Array:
	## Oyuncunun ihtiyaci tam liste degil, "en yakin acik nerede" bilgisidir.
	var ordered := leaks.duplicate()
	ordered.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return Vector2(a - origin).length_squared() < Vector2(b - origin).length_squared())
	var seen: Array = []
	for cell: Vector2i in ordered:
		var close := false
		for s: Vector2i in seen:
			if absi(cell.x - s.x) + absi(cell.y - s.y) <= 3:
				close = true
				break
		if close:
			continue
		seen.append(cell)
		if seen.size() >= MAX_REPORTED_LEAKS:
			break
	return seen


func to_dict() -> Dictionary:
	# `interior` kaydedilmez: haritadan ve barikatlardan yeniden uretilir.
	return {"id": id, "name": name, "seed": [seed_cell.x, seed_cell.y, seed_y],
		"day_founded": day_founded, "population": population, "roles": roles.duplicate(),
		"stockpile": stockpile.to_dict(), "breached": breached}


static func from_dict(data: Dictionary) -> Settlement:
	var s := Settlement.new()
	s.id = str(data.get("id", "base1"))
	s.name = str(data.get("name", "Us"))
	var seed: Array = data.get("seed", [0, 0, 0])
	s.seed_cell = Vector2i(int(seed[0]), int(seed[1]))
	s.seed_y = int(seed[2]) if seed.size() > 2 else 0
	s.day_founded = int(data.get("day_founded", 1))
	s.population = int(data.get("population", 1))
	s.breached = bool(data.get("breached", false))
	for building_id: String in data.get("roles", {}):
		var role := str(data.roles[building_id])
		if role in ROLES:
			s.roles[building_id] = role
	s.stockpile.load_dict(data.get("stockpile", {}), Content.items)
	return s
