class_name WorldProps
extends Node3D
## Dunyaya yerlestirilen etkilesimli / dekoratif GLB nesneleri: cesme,
## sadirvan, el pompasi, gorev nesneleri (role konsolu, pompa pervanesi,
## sinyal isareti...), semt kimligi nesneleri.
##
## KURALLAR
##   * Konum veriden gelir (OSM noktasi, cami, park, gorev tanimi); nesne
##     KIMLIGI sabittir ("su:w123", "gorev:q_relay_1"). Kayit kimlige baglanir.
##   * Gorsel yakinda kurulur (70 m), uzakta birakilir. Carpisma voxel degil
##     basit kutudur (VoxelBody extra_boxes); modelin gorselinden buyuk
##     gizli kutu yoktur: kutu manifestin olcusunden, zemine oturtulmus.
##   * Zemine oturtma ilk kurulumda yapilir (sutun bilgisi hazirsa); oturmadan
##     etkilesim acilmaz.

const SPAWN_RADIUS := 70.0
const FREE_RADIUS := 95.0
const TILE := 32.0

var city: CityGenerator
var world: VoxelWorld
var entries: Array = []            # {id, asset, pos, yaw, kind, label, solid, snapped, data}
var by_id: Dictionary = {}
var _grid: Dictionary = {}          # Vector2i -> [indeks]
var _nodes: Dictionary = {}         # indeks -> Node3D
var _timer := 0.0


func setup(p_city: CityGenerator, p_world: VoxelWorld) -> void:
	city = p_city
	world = p_world


func add(entry: Dictionary) -> int:
	## entry: {id, asset, pos: Vector3 (y yoksa zemine oturur), yaw, kind, label, solid}
	if by_id.has(entry.id):
		return by_id[entry.id]
	var e := entry.duplicate()
	e["snapped"] = e.get("snapped", false)
	e["solid"] = e.get("solid", true)
	e["yaw"] = float(e.get("yaw", 0.0))
	e["data"] = e.get("data", {})
	var index := entries.size()
	entries.append(e)
	by_id[e.id] = index
	var key := Vector2i(floori(e.pos.x / TILE), floori(e.pos.z / TILE))
	if not _grid.has(key):
		_grid[key] = []
	_grid[key].append(index)
	return index


func remove(id: String) -> void:
	if not by_id.has(id):
		return
	var index: int = by_id[id]
	if _nodes.has(index):
		_nodes[index].queue_free()
		_nodes.erase(index)
	entries[index]["removed"] = true


func get_entry(id: String) -> Dictionary:
	return entries[by_id[id]] if by_id.has(id) else {}


func _near(position: Vector3, radius: float) -> Array:
	var result: Array = []
	var r := ceili(radius / TILE)
	var c := Vector2i(floori(position.x / TILE), floori(position.z / TILE))
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			for index: int in _grid.get(c + Vector2i(dx, dz), []):
				var e: Dictionary = entries[index]
				if e.get("removed", false):
					continue
				if Vector2(e.pos.x - position.x, e.pos.z - position.z).length() <= radius:
					result.append(index)
	return result


func update(delta: float, position: Vector3) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.5
	var keep := {}
	var spawned := 0
	for index: int in _near(position, SPAWN_RADIUS):
		keep[index] = true
		if not _nodes.has(index) and spawned < 4:
			_spawn(index)
			spawned += 1
	for index: int in _nodes.keys():
		if keep.has(index):
			continue
		var e: Dictionary = entries[index]
		if Vector2(e.pos.x - position.x, e.pos.z - position.z).length() > FREE_RADIUS:
			_nodes[index].queue_free()
			_nodes.erase(index)


func _spawn(index: int) -> void:
	var e: Dictionary = entries[index]
	if not bool(e.snapped):
		if not _snap(e):
			return          # zemin henuz yuklenmedi: bir sonraki turda
	var node := AssetLibrary.instantiate(str(e.asset))
	node.name = str(e.id).replace(":", "_")
	add_child(node)
	node.position = e.pos
	node.rotation.y = float(e.yaw)
	_nodes[index] = node


func _snap(e: Dictionary) -> bool:
	## Nesneyi en yakin acik yurunebilir hucreye ve zemine oturtur. Bina
	## icine denk gelen nokta (cami merkezi gibi) disari, cephe onune tasinir.
	var cx := floori(e.pos.x)
	var cz := floori(e.pos.z)
	# Konum harita adiminda zaten disarida secilir; burada yalnizca yakin
	# duzeltme (en fazla 8 m). Genis sutun taramasi akista takilma yapiyordu.
	for r in range(0, 9):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				var x := cx + dx
				var z := cz + dz
				var info := city.column_info(x, z)
				if not info.kind in ["sidewalk", "plaza", "ground", "park", "road"] or int(info.building) >= 0 \
						or bool(info.tree) or info.has("bridge"):
					continue
				if not world.is_open_column(x, z):
					continue
				# Bina bitisik (sadirvan cami duvarinin dibinde) ama yol ortasi degil.
				if info.kind == "road" and e.kind != "mission":
					continue
				e.pos = Vector3(x + 0.5, city.surface_y(x, z), z + 0.5)
				# Yuzu en yakin binaya donuk (cesme duvara yasli durur).
				for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					if int(city.column_info(x + d.x, z + d.y).building) >= 0:
						e.yaw = atan2(float(d.x), float(d.y))
						break
				e.snapped = true
				return true
	e.snapped = true    # uygun yer yok: oldugu yerde kalir
	e.pos.y = city.surface_y(cx, cz)
	return true


func boxes_near(position: Vector3) -> Array:
	## Katı nesnelerin carpisma kutulari (manifest olcusu, ekseni hizali).
	var result: Array = []
	for index: int in _near(position, 6.0):
		var e: Dictionary = entries[index]
		if not bool(e.solid) or not bool(e.snapped):
			continue
		var b := AssetLibrary.bounds(str(e.asset))
		var half := Vector2(maxf(absf(b.position.x), absf(b.end.x)), maxf(absf(b.position.z), absf(b.end.z)))
		var s := absf(sin(float(e.yaw)))
		var c := absf(cos(float(e.yaw)))
		var hx := half.x * c + half.y * s
		var hz := half.x * s + half.y * c
		result.append([Vector3(e.pos.x - hx, e.pos.y, e.pos.z - hz),
			Vector3(e.pos.x + hx, e.pos.y + b.end.y, e.pos.z + hz)])
	return result


func nearest(position: Vector3, radius: float, kinds: Array = []) -> Dictionary:
	var best := {}
	var best_d := radius
	for index: int in _near(position, radius + 1.0):
		var e: Dictionary = entries[index]
		if not kinds.is_empty() and not e.kind in kinds:
			continue
		if not bool(e.snapped):
			continue
		var d := Vector3(e.pos.x, position.y, e.pos.z).distance_to(position)
		if absf(e.pos.y - position.y) > 2.5:
			continue
		if d <= best_d:
			best_d = d
			best = e
	return best


func loaded_count() -> int:
	return _nodes.size()
