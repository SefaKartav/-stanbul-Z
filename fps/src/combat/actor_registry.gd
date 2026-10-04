class_name ActorRegistry
extends RefCounted
## Canli varliklar (zombi, NPC, oyuncu) icin ortak sorgu noktasi.
##
## Her aktor su yontemleri saglar:
##   hit_test(origin, dir, max_distance) -> {"distance": float, "zone": "body"|"head"} ya da {}
##   receive_damage(amount, damage_type, direction, point, source, zone) -> {"dealt", "killed"}
##   faction() -> String            ("zombie", "survivor", "player")
##   is_alive() -> bool
##   global_position (Node3D)
## Kaba bir izgara (8 m) ile yakin aktorler hizla bulunur; isin sorgusu
## ve gurultu yayilimi tum listeyi taramaz.

const CELL := 8.0

var actors: Array = []
var _grid: Dictionary = {}          # Vector2i -> Array
var _grid_dirty := true


func add(actor: Object) -> void:
	if not actors.has(actor):
		actors.append(actor)
		_grid_dirty = true


func remove(actor: Object) -> void:
	actors.erase(actor)
	_grid_dirty = true


func rebuild() -> void:
	## Kare basina bir kez (aktorler hareket ettikten sonra) cagrilir.
	_grid.clear()
	actors = actors.filter(func(a: Object) -> bool: return is_instance_valid(a))
	for actor: Node3D in actors:
		var key := _key(actor.global_position)
		if not _grid.has(key):
			_grid[key] = []
		_grid[key].append(actor)
	_grid_dirty = false


static func _key(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.z / CELL))


func near(position: Vector3, radius: float) -> Array:
	if _grid_dirty:
		rebuild()
	var result: Array = []
	var r := int(ceil(radius / CELL))
	var c := _key(position)
	var r2 := radius * radius
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			for actor: Node3D in _grid.get(Vector2i(c.x + dx, c.y + dz), []):
				if is_instance_valid(actor) and actor.global_position.distance_squared_to(position) <= r2:
					result.append(actor)
	return result


func raycast(origin: Vector3, direction: Vector3, max_distance: float, ignore_faction: String,
		ignore: Object = null) -> Array:
	## Isin uzerindeki aktorler, YAKINDAN UZAGA: [{actor, distance, zone}]
	var hits: Array = []
	for actor: Node3D in actors:
		if actor == ignore or not is_instance_valid(actor) or not actor.is_alive():
			continue
		if ignore_faction != "" and actor.faction() == ignore_faction:
			continue
		# Kaba eleme: isina olan dik uzaklik 2 m'den fazlaysa atla.
		var to := actor.global_position - origin
		var along := to.dot(direction)
		if along < -1.0 or along > max_distance + 1.0:
			continue
		if (to - direction * along).length_squared() > 4.0:
			continue
		var hit: Dictionary = actor.hit_test(origin, direction, max_distance)
		if not hit.is_empty():
			hit["actor"] = actor
			hits.append(hit)
	hits.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.distance < b.distance)
	return hits


func of_faction(faction: String) -> Array:
	return actors.filter(func(a: Object) -> bool:
		return is_instance_valid(a) and a.faction() == faction and a.is_alive())


static func ray_box(origin: Vector3, direction: Vector3, bmin: Vector3, bmax: Vector3, max_distance: float) -> float:
	## Isin-kutu kesisimi (slab yontemi). Giris mesafesi ya da -1.
	var t_min := 0.0
	var t_max := max_distance
	for axis in 3:
		var o := origin[axis]
		var d := direction[axis]
		if absf(d) < 1e-8:
			if o < bmin[axis] or o > bmax[axis]:
				return -1.0
			continue
		var inv := 1.0 / d
		var t1 := (bmin[axis] - o) * inv
		var t2 := (bmax[axis] - o) * inv
		if t1 > t2:
			var tmp := t1
			t1 = t2
			t2 = tmp
		t_min = maxf(t_min, t1)
		t_max = minf(t_max, t2)
		if t_min > t_max:
			return -1.0
	return t_min
