class_name VoxelBody
extends RefCounted
## Voxel dunyasina karsi AABB hareketi (oyuncu, zombi, NPC).
##
## NEDEN GODOT FIZIGI DEGIL?
##   Kirilabilir dunyada fizik collider'i ayri bir kopya olurdu ve her
##   blok degisiminde yeniden kurulmasi gerekirdi. Kopya gecikirse ya
##   "gorunmez duvar" ya da "icinden gecilen blok" olusur -- belgenin
##   ozellikle yasakladigi iki hata. Bu sinif dogrudan VoxelWorld'u okur:
##   kirilan blok ANINDA gecilebilir, konan blok ANINDA engeldir.
##
## Algoritma, Minecraft'in da kullandigi eksen-eksen kirpmadir: once Y,
## sonra X, sonra Z. Her eksende hareket, yolundaki kutularin en yakinina
## kadar kisaltilir. Tunneling olmaz; hiz ne olursa olsun kutu atlanamaz.

const EPS := 0.001

## Sonuc sozlugu: {position, velocity, on_floor, hit_ceiling, hit_wall}


static func move(world: VoxelWorld, position: Vector3, velocity: Vector3, dt: float,
		half_width: float, height: float, step_height: float, was_on_floor: bool,
		extra_boxes: Array = []) -> Dictionary:
	var motion := velocity * dt
	var box_min := Vector3(position.x - half_width, position.y, position.z - half_width)
	var box_max := Vector3(position.x + half_width, position.y + height, position.z + half_width)
	var boxes := _collect(world, box_min, box_max, motion, step_height, extra_boxes)

	var result := _sweep(boxes, box_min, box_max, motion)
	var moved: Vector3 = result.motion

	# BASAMAK: yatayda takildiysak ve yerdeysek, basamak yuksekligi kadar
	# yukaridan tekrar dene. Kaldirim (0.5 m) boylece zıplamadan cikilir;
	# tam blok (1 m) icin zıplamak gerekir.
	if step_height > 0.0 and (was_on_floor or result.on_floor) and result.hit_wall:
		var up := _sweep(boxes, box_min, box_max, Vector3(0, step_height, 0))
		var lifted_min: Vector3 = box_min + up.motion
		var lifted_max: Vector3 = box_max + up.motion
		var across := _sweep(boxes, lifted_min, lifted_max, Vector3(motion.x, 0, motion.z))
		var across_min: Vector3 = lifted_min + across.motion
		var across_max: Vector3 = lifted_max + across.motion
		var down := _sweep(boxes, across_min, across_max, Vector3(0, -up.motion.y - EPS * 2.0 + minf(0.0, motion.y), 0))
		var stepped: Vector3 = up.motion + across.motion + down.motion
		var flat_before := Vector2(moved.x, moved.z).length_squared()
		var flat_after := Vector2(stepped.x, stepped.z).length_squared()
		if flat_after > flat_before + EPS and down.on_floor:
			moved = stepped
			result.hit_wall = across.hit_wall
			result.on_floor = true

	var new_velocity := velocity
	if absf(moved.x - motion.x) > EPS:
		new_velocity.x = 0.0
	if absf(moved.z - motion.z) > EPS:
		new_velocity.z = 0.0
	if result.on_floor and new_velocity.y < 0.0:
		new_velocity.y = 0.0
	if result.hit_ceiling and new_velocity.y > 0.0:
		new_velocity.y = 0.0
	return {
		"position": position + moved,
		"velocity": new_velocity,
		"on_floor": result.on_floor,
		"hit_ceiling": result.hit_ceiling,
		"hit_wall": result.hit_wall,
	}


static func _collect(world: VoxelWorld, box_min: Vector3, box_max: Vector3, motion: Vector3,
		step_height: float, extra_boxes: Array) -> Array:
	## Hareket suresince degebilecek tum katı hucre kutulari.
	var lo := box_min + Vector3(minf(0.0, motion.x), minf(0.0, motion.y) - 0.1, minf(0.0, motion.z))
	var hi := box_max + Vector3(maxf(0.0, motion.x), maxf(0.0, motion.y) + step_height + 0.1, maxf(0.0, motion.z))
	var boxes: Array = []
	for y in range(floori(lo.y) - 1, floori(hi.y) + 1):
		for z in range(floori(lo.z), floori(hi.z) + 1):
			for x in range(floori(lo.x), floori(hi.x) + 1):
				var h := world.cell_height(world.get_block(x, y, z))
				if h <= 0.0:
					continue
				var bmin := Vector3(x, y, z)
				var bmax := Vector3(x + 1, y + h, z + 1)
				if bmax.y <= lo.y or bmin.y >= hi.y:
					continue
				boxes.append([bmin, bmax])
	for extra: Array in extra_boxes:
		var emin: Vector3 = extra[0]
		var emax: Vector3 = extra[1]
		if emax.x > lo.x and emin.x < hi.x and emax.y > lo.y and emin.y < hi.y and emax.z > lo.z and emin.z < hi.z:
			boxes.append(extra)
	return boxes


static func _sweep(boxes: Array, box_min: Vector3, box_max: Vector3, motion: Vector3) -> Dictionary:
	var lo := box_min
	var hi := box_max
	var result := {"motion": Vector3.ZERO, "on_floor": false, "hit_ceiling": false, "hit_wall": false}
	# Baslangicta icinde oldugumuz kutular yok sayilir (sikisma durumunda
	# hareket donmasin; itme ayri cozulur).
	var active: Array = []
	for box: Array in boxes:
		if not _overlaps(lo, hi, box[0], box[1]):
			active.append(box)

	# Y
	var dy := motion.y
	for box: Array in active:
		var bmin: Vector3 = box[0]
		var bmax: Vector3 = box[1]
		if hi.x <= bmin.x + EPS or lo.x >= bmax.x - EPS or hi.z <= bmin.z + EPS or lo.z >= bmax.z - EPS:
			continue
		if dy < 0.0 and lo.y >= bmax.y - EPS:
			dy = maxf(dy, bmax.y - lo.y)
		elif dy > 0.0 and hi.y <= bmin.y + EPS:
			dy = minf(dy, bmin.y - hi.y)
	# Asagi hareket kirpildiysa bir seyin ustunde duruyoruz.
	if motion.y < 0.0 and dy > motion.y + EPS * 0.5:
		result.on_floor = true
	if motion.y > 0.0 and dy < motion.y - EPS:
		result.hit_ceiling = true
	lo.y += dy
	hi.y += dy

	# X
	var dx := motion.x
	for box: Array in active:
		var bmin: Vector3 = box[0]
		var bmax: Vector3 = box[1]
		if hi.y <= bmin.y + EPS or lo.y >= bmax.y - EPS or hi.z <= bmin.z + EPS or lo.z >= bmax.z - EPS:
			continue
		if dx > 0.0 and hi.x <= bmin.x + EPS:
			dx = minf(dx, bmin.x - hi.x)
		elif dx < 0.0 and lo.x >= bmax.x - EPS:
			dx = maxf(dx, bmax.x - lo.x)
	if absf(dx - motion.x) > EPS:
		result.hit_wall = true
	lo.x += dx
	hi.x += dx

	# Z
	var dz := motion.z
	for box: Array in active:
		var bmin: Vector3 = box[0]
		var bmax: Vector3 = box[1]
		if hi.y <= bmin.y + EPS or lo.y >= bmax.y - EPS or hi.x <= bmin.x + EPS or lo.x >= bmax.x - EPS:
			continue
		if dz > 0.0 and hi.z <= bmin.z + EPS:
			dz = minf(dz, bmin.z - hi.z)
		elif dz < 0.0 and lo.z >= bmax.z - EPS:
			dz = maxf(dz, bmax.z - lo.z)
	if absf(dz - motion.z) > EPS:
		result.hit_wall = true

	result.motion = Vector3(dx, dy, dz)
	return result


static func _overlaps(amin: Vector3, amax: Vector3, bmin: Vector3, bmax: Vector3) -> bool:
	return amax.x > bmin.x + EPS and amin.x < bmax.x - EPS \
		and amax.y > bmin.y + EPS and amin.y < bmax.y - EPS \
		and amax.z > bmin.z + EPS and amin.z < bmax.z - EPS


static func is_blocked(world: VoxelWorld, position: Vector3, half_width: float, height: float,
		extra_boxes: Array = []) -> bool:
	## Bu konumda govde bir katı hucreyle ya da kutuyla cakisiyor mu?
	var lo := Vector3(position.x - half_width, position.y, position.z - half_width)
	var hi := Vector3(position.x + half_width, position.y + height, position.z + half_width)
	for y in range(floori(lo.y), floori(hi.y - EPS) + 1):
		for z in range(floori(lo.z), floori(hi.z - EPS) + 1):
			for x in range(floori(lo.x), floori(hi.x - EPS) + 1):
				var h := world.cell_height(world.get_block(x, y, z))
				if h > 0.0 and _overlaps(lo, hi, Vector3(x, y, z), Vector3(x + 1, y + h, z + 1)):
					return true
	for extra: Array in extra_boxes:
		if _overlaps(lo, hi, extra[0], extra[1]):
			return true
	return false


static func unstick(world: VoxelWorld, position: Vector3, half_width: float, height: float,
		extra_boxes: Array = []) -> Vector3:
	## Govde bir kutuya gomulduyse (orn. yukleme sonrasi) en yakin bos
	## konuma yukari dogru iter. Harita disina ya da suya dusmeyi onler.
	if not is_blocked(world, position, half_width, height, extra_boxes):
		return position
	for step in range(1, 64):
		var candidate := position + Vector3(0, step * 0.5, 0)
		if not is_blocked(world, candidate, half_width, height, extra_boxes):
			return candidate
	return position
