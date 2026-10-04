class_name TestSiteGenerator
extends RefCounted
## Faz A/B blok test sahasi: 128 x 128 m.
##
##   * x ekseni boyunca asfalt yol, iki yanda yarim blok kaldirim
##   * kuzey kaldiriminda 5 malzemeden deneme duvarlari
##     (ahsap, cam, tugla, beton, celik) -- ayni silahla farkli atis sayisi
##   * uc katli, cepheli, ici dolu bir apartman
##   * guneyde kiyi ve su
## Is parcacigi guvenlidir: yalnizca kendi sabit verisini okur.

const HALF := 64

var m: Dictionary = {}


func _init(materials: BlockMaterials) -> void:
	for id: String in materials.defs:
		m[id] = materials.index_of(id)


func configure(world: VoxelWorld) -> void:
	world.min_cell = Vector3i(-HALF, -16, -HALF)
	world.max_cell = Vector3i(HALF, 48, HALF)


func spawn_point() -> Vector3:
	return Vector3(0.5, 0.0, 6.0)


func ground_height(_x: int, _z: int) -> int:
	## Yol bulma icin beklenen zemin (ilk bos hucrenin y'si).
	return 0


func generate_chunk(chunk: VoxelChunk) -> void:
	var origin := chunk.origin()
	for ly in VoxelChunk.SIZE:
		var y := origin.y + ly
		for lz in VoxelChunk.SIZE:
			var z := origin.z + lz
			for lx in VoxelChunk.SIZE:
				var x := origin.x + lx
				var value := block_at(x, y, z)
				if value != 0:
					chunk.blocks[VoxelChunk.index(lx, ly, lz)] = value


func block_at(x: int, y: int, z: int) -> int:
	var coast := z < -40
	# --- zemin ---
	if y < -1:
		if coast:
			return m.water if y >= -4 else m.sand if y >= -6 else m.stone
		return m.dirt if y >= -4 else m.stone
	if y == -1:
		if coast:
			return m.water
		if z >= -4 and z <= 4:
			return m.asphalt
		if z == -40 or z == -39:
			return m.stone
		return m.dirt if absi(z) <= 7 else m.grass
	# --- kaldirimlar ---
	if y == 0 and ((z >= 5 and z <= 7) or (z >= -7 and z <= -5)):
		return m.sidewalk
	if y == 0 and (z == -39) and x % 3 != 0:
		return m.railing
	# --- deneme duvarlari (kuzey) ---
	if z == 11 and y >= 0 and y <= 2:
		var walls := ["wood", "glass", "brick", "concrete", "steel", "sandbag", "concrete_block"]
		var slot := floori((x + 30) / 6.0)
		var local := (x + 30) - slot * 6
		if slot >= 0 and slot < walls.size() and local >= 0 and local < 4:
			return m[walls[slot]]
	# --- apartman ---
	var b := _building(x, y, z, 14, 16, 12, 10, 9)
	if b != 0:
		return b
	var b2 := _building(x, y, z, -34, 16, 8, 9, 12)
	if b2 != 0:
		return b2
	# --- agac ---
	if (x == 30 or x == -12) and z == 9:
		if y >= 0 and y < 4:
			return m.log
	if absi(x - 30) <= 2 and absi(z - 9) <= 2 and y >= 3 and y <= 5:
		return m.leaves
	return 0


func _building(x: int, y: int, z: int, bx: int, bz: int, w: int, d: int, h: int) -> int:
	if x < bx or x >= bx + w or z < bz or z >= bz + d or y < 0 or y >= h + 1:
		return 0
	var edge := x == bx or x == bx + w - 1 or z == bz or z == bz + d - 1
	if y == h:
		return m.roof_flat if not edge else m.concrete
	if not edge:
		# Test sahasi binalari bilerek DOLU malzeme hacmidir (yikim testleri
		# icin); girilebilir ic mekanlar yalnizca sehir haritalarinda uretilir.
		return m.interior if (y % 3 != 0) else m.concrete
	# Cephe: kat kirisleri beton, aralar siva, pencereler cam.
	if y % 3 == 0:
		return m.concrete
	var along := (x - bx) if (z == bz or z == bz + d - 1) else (z - bz)
	var corner := (x == bx or x == bx + w - 1) and (z == bz or z == bz + d - 1)
	if not corner and y % 3 == 1 and along % 3 == 1:
		return m.glass
	if not corner and y % 3 == 2 and along % 3 == 1:
		return m.glass
	# Zemin katta dukkan kapisi: oyuncu iceri GIREMEZ ama kepenk kirilabilir.
	if y <= 2 and z == bz and (x - bx) >= 4 and (x - bx) <= 6:
		return m.metal_sheet
	return m.plaster_cream if (bx > 0) else m.brick
