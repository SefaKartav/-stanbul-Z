class_name TestWalker
extends RefCounted
## Test araci: GERCEK oyuncu govdesiyle (VoxelBody, 0.6 x 1.8 m) 3B yurume
## grafigi. Durum = (hucre x, 2 x ayak yuksekligi, hucre z). Komsu hucreye
## ayni seviyede, 0.5 m basamak cikarak (VoxelBody STEP 0.55) ya da en fazla
## 2 m inerek gecilir; gecis sirasinda ara noktada da govde sigmali. Tirmanma
## merdiveni hucresinde (climbable) dikey 0.5 m adimlarla cikilip inilir ve
## oradan kata adim atilir (Player: tirmanirken basamak payi acik).

const HALF := 0.3
const HEIGHT := 1.8
const DYS: Array[float] = [0.0, 0.5, -0.5, -1.0, -1.5, -2.0]


static func key(c: Vector2i, y: float) -> Vector3i:
	return Vector3i(c.x, roundi(y * 2.0), c.y)


static func climbable_at(world: VoxelWorld, c: Vector2i, y: float) -> bool:
	## Govdenin alt yarisi bir tirmanma hucresine degiyor mu? (Player._touching_ladder)
	for cy in range(floori(y), floori(y + HEIGHT * 0.5) + 1):
		var v := world.get_block(c.x, cy, c.y)
		if v > 0 and v != VoxelWorld.BOUNDARY and world.materials.climbable[v] == 1:
			return true
	return false


static func _standable(world: VoxelWorld, c: Vector2i, y: float) -> bool:
	var pos := Vector3(c.x + 0.5, y + 0.02, c.y + 0.5)
	if VoxelBody.is_blocked(world, pos, HALF, HEIGHT):
		return false
	if VoxelBody.is_blocked(world, pos - Vector3(0, 0.1, 0), HALF, HEIGHT):
		return true            # zeminde
	return climbable_at(world, c, y)


static func walk(world: VoxelWorld, start: Vector2i, start_y: float, lo: Vector2i, hi: Vector2i,
		y_min: float, y_max: float) -> Dictionary:
	## Donus: Vector3i(x, 2y, z) -> true (ulasilan durus noktalari).
	var reach := {key(start, start_y): true}
	var queue: Array = [[start, start_y]]
	while not queue.is_empty():
		var item: Array = queue.pop_front()
		var c: Vector2i = item[0]
		var here: float = item[1]
		# Tirmanma: ayni hucrede yukari/asagi.
		if climbable_at(world, c, here):
			for dy: float in [0.5, -0.5]:
				var y := here + dy
				var k := key(c, y)
				if y < y_min or y > y_max or reach.has(k):
					continue
				if _standable(world, c, y):
					reach[k] = true
					queue.append([c, y])
		var climbing := climbable_at(world, c, here)
		for d: Vector2i in InteriorPlanner.DIRS:
			var n := c + d
			if n.x < lo.x or n.y < lo.y or n.x > hi.x or n.y > hi.y:
				continue
			for dy: float in DYS:
				var y := here + dy
				if y < y_min or y > y_max:
					continue
				var k := key(n, y)
				if reach.has(k):
					continue
				if not _standable(world, n, y):
					continue
				var mid := Vector3(c.x + 0.5 + d.x * 0.5, maxf(y, here) + 0.02, c.y + 0.5 + d.y * 0.5)
				if VoxelBody.is_blocked(world, mid, HALF, HEIGHT):
					continue
				if dy > 0.0 and climbing and dy > 0.55:
					continue
				reach[k] = true
				queue.append([n, y])
				break
	return reach


static func reached(reach: Dictionary, c: Vector2i, y: float) -> bool:
	return reach.has(key(c, y))


static func floor_reached(reach: Dictionary, plan: Dictionary, k: int) -> bool:
	## Katin kendi hucrelerinden birinde kat seviyesinde durulabildi mi?
	var y := float(plan.floors[k].y)
	var yk := roundi(y * 2.0)
	var fl: Dictionary = plan.floors[k]
	for room: Dictionary in fl.get("rooms", []):
		for c: Vector2i in room.cells:
			if reach.has(Vector3i(c.x, yk, c.y)):
				return true
	return false


static func world_around(city: CityGenerator, plan: Dictionary, top_y: int) -> VoxelWorld:
	var world := VoxelWorld.new(Content.blocks)
	city.configure(world)
	world.generator = city
	var o: Vector2i = plan.origin
	var s: Vector2i = plan.size
	var y0: int = plan.floors[0].y
	var lo := VoxelWorld.chunk_of(Vector3i(o.x - 4, y0 - 3, o.y - 4))
	var hi := VoxelWorld.chunk_of(Vector3i(o.x + s.x + 4, top_y + 4, o.y + s.y + 4))
	for cy in range(lo.y, hi.y + 1):
		for cz in range(lo.z, hi.z + 1):
			for cx in range(lo.x, hi.x + 1):
				world.ensure_chunk(Vector3i(cx, cy, cz))
	return world


static func open_door(world: VoxelWorld, plan: Dictionary) -> void:
	var door: Dictionary = plan.doors[0]
	for c in int(door.get("rows", 2)):
		world.set_block(Vector3i(door.cell.x, plan.floors[0].y + c, door.cell.y), 0, VoxelWorld.ORIGIN_WORLD)


static func headroom_ok(world: VoxelWorld, reach: Dictionary, tops: Dictionary, y0: float, need: float = 2.05) -> Array:
	## Merdiven BASAMAKLARININ uzerinde (tops: hucre -> basamak yuksekligi t,
	## durus y = y0 + 4k + t) ulasilan her noktada `need` m bos yukseklik var
	## mi? Merdivenin altinda durmak (yurume rotasi degil) sayilmaz.
	## Donus: [yetersiz nokta sayisi, en kotu bas boslugu, denetlenen nokta].
	var bad := 0
	var worst := 99.0
	var checked := 0
	for s: Vector3i in reach:
		var c := Vector2i(s.x, s.z)
		if not tops.has(c):
			continue
		var y := s.y * 0.5
		var rel := fposmod(y - y0 - float(tops[c]), 4.0)
		if rel > 0.01 and rel < 3.99:
			continue
		checked += 1
		var clear := 0.0
		for step in range(1, 12):
			var h := step * 0.25
			if VoxelBody.is_blocked(world, Vector3(c.x + 0.5, y + 0.02, c.y + 0.5), 0.29, h):
				break
			clear = h
		worst = minf(worst, clear)
		if clear + 0.001 < need:
			bad += 1
	return [bad, worst, checked]
