class_name ChunkMesher
extends RefCounted
## Tek bir chunk'in gorsel mesh'ini uretir. SAF FONKSIYON: girdi olarak
## kenar pay'li (18^3) bir kopya alir ve dunyaya dokunmaz; bu sayede arka
## plan is parcaciginda guvenle calisir. Ana is parcacigi sonucu, chunk
## surumu hala ayniysa uygular (bkz. VoxelTerrain).
##
## Neden her yuz ayri dortgen (greedy birlestirme yok)?
##   Kose AO'su, blok basi renk tonu ve hasar catlagi blok basina degisir;
##   birlestirilmis dev dortgenler bunlari tasiyamaz. Olcum yapilmadan
##   karmasiklik eklemedik: bir chunk'in gorunur yuzu genelde birkac bin.
##
## Kose verisi:
##   UV   -- blok biriminde doku koordinati
##   UV2  -- x: doku atlas katmani, y: hasar kademesi (0-3)
##   COLOR-- rgb: AO x blok tonu

const P := 18                 # kenar pay'li kenar uzunlugu
const P2 := P * P
const AO_LEVELS := [0.52, 0.68, 0.84, 1.0]

# Yuz tanimlari: normal, 4 kose (birim kup), teğet eksenleri.
const FACES := [
	{"n": Vector3i(1, 0, 0), "c": [Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(1, 1, 1), Vector3(1, 0, 1)]},
	{"n": Vector3i(-1, 0, 0), "c": [Vector3(0, 0, 1), Vector3(0, 1, 1), Vector3(0, 1, 0), Vector3(0, 0, 0)]},
	{"n": Vector3i(0, 1, 0), "c": [Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 1, 1), Vector3(0, 1, 1)]},
	{"n": Vector3i(0, -1, 0), "c": [Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(1, 0, 0), Vector3(0, 0, 0)]},
	{"n": Vector3i(0, 0, 1), "c": [Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(0, 1, 1), Vector3(0, 0, 1)]},
	{"n": Vector3i(0, 0, -1), "c": [Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 0, 0)]},
]

static var _prepared := false
static var _corners: Array = []        # [yuz][kose] -> Vector3 (Godot sarim yonunde)
static var _ao_offsets: Array = []     # [yuz][kose] -> [yan1, yan2, kose] pay'li indeks farki
static var _normal_offset: PackedInt32Array


static func _prepare() -> void:
	## Kose sirasini Godot'un on yuz kuralina (saat yonu) gore duzeltir ve
	## AO komsu ofsetlerini onceden hesaplar.
	if _prepared:
		return
	_normal_offset = PackedInt32Array()
	for face: Dictionary in FACES:
		var n: Vector3i = face.n
		var corners: Array = face.c.duplicate()
		var edge1: Vector3 = corners[1] - corners[0]
		var edge2: Vector3 = corners[2] - corners[0]
		var cross := edge1.cross(edge2)
		# Godot'ta on yuz saat yonundedir: capraz carpim DISA degil ICE bakmali.
		if cross.dot(Vector3(n)) > 0.0:
			corners.reverse()
		_corners.append(corners)
		_normal_offset.append(_offset(n.x, n.y, n.z))
		var per_corner: Array = []
		for corner: Vector3 in corners:
			# Tegetsel eksenlerde kosenin gosterdigi yon (-1 / +1).
			var d := Vector3i(int(corner.x) * 2 - 1, int(corner.y) * 2 - 1, int(corner.z) * 2 - 1)
			var a := Vector3i.ZERO
			var b := Vector3i.ZERO
			if n.x != 0:
				a = Vector3i(0, d.y, 0)
				b = Vector3i(0, 0, d.z)
			elif n.y != 0:
				a = Vector3i(d.x, 0, 0)
				b = Vector3i(0, 0, d.z)
			else:
				a = Vector3i(d.x, 0, 0)
				b = Vector3i(0, d.y, 0)
			var base := n
			per_corner.append([
				_offset(base.x + a.x, base.y + a.y, base.z + a.z),
				_offset(base.x + b.x, base.y + b.y, base.z + b.z),
				_offset(base.x + a.x + b.x, base.y + a.y + b.y, base.z + a.z + b.z),
			])
		_ao_offsets.append(per_corner)
	_prepared = true


static func _offset(dx: int, dy: int, dz: int) -> int:
	return (dy * P + dz) * P + dx


static func padded_index(x: int, y: int, z: int) -> int:
	## x,y,z: -1..16 (chunk yerel)
	return ((y + 1) * P + (z + 1)) * P + (x + 1)


static func build(padded: PackedByteArray, stages: Dictionary, chunk_origin: Vector3i,
		materials: BlockMaterials, lod: int = 0) -> Dictionary:
	## lod 1 (uzak chunk): yalnizca ic mekanda gorulen malzemeler (ic siva,
	## parke, fayans, basamak) meshlenmez. Dis cephe ve cati aynidir; oyuncu
	## yaklasinca chunk lod 0 ile yeniden meshlenir (VoxelTerrain).
	## Sonuc: {"opaque": arrays|null, "transparent": arrays|null}
	## `stages`: yerel indeks (0..4095) -> hasar kademesi (yalnizca hasarlilar).
	_prepare()
	var opaque := _Surface.new()
	var clear := _Surface.new()
	var solid := materials.solid
	var opaque_flags := materials.opaque
	var transparent := materials.transparent
	var liquid := materials.liquid
	var shape := materials.shape
	var tex_top := materials.tex_top
	var tex_side := materials.tex_side
	var tex_bottom := materials.tex_bottom
	var hidden := materials.hidden
	var smooth := materials.smooth
	var inner := materials.inner

	for ly in 16:
		for lz in 16:
			var row := ((ly + 1) * P + (lz + 1)) * P + 1
			for lx in 16:
				var i := row + lx
				var value := padded[i]
				if value == 0 or hidden[value] == 1:
					continue      # hava ya da gorunmez carpisma hacmi (mobilya/kapi)
				if lod >= 1 and inner[value] == 1:
					continue      # uzak chunk: ic mekan yuzeyi cizilmez
				var is_clear := transparent[value] == 1 or liquid[value] == 1
				var is_slab := shape[value] == BlockMaterials.SHAPE_SLAB
				var surface: _Surface = clear if is_clear else opaque
				var local_index := (ly * 16 + lz) * 16 + lx
				var stage: int = stages.get(local_index, 0)
				# Yol yuzeyleri (asfalt, kaldirim, cizgi): blok basina ton farki cok az;
				# yol kup kup benek degil tek yuzey gibi okunur.
				var tint := _tint(chunk_origin.x + lx, chunk_origin.y + ly, chunk_origin.z + lz)
				if smooth[value] == 1:
					tint = 0.97 + (tint - 0.9) * 0.2
				for f in 6:
					var neighbour := padded[i + _normal_offset[f]]
					if not _face_visible(value, neighbour, f, is_slab, is_clear, opaque_flags, shape, solid):
						continue
					var layer: int
					if f == 2:
						layer = tex_top[value]
					elif f == 3:
						layer = tex_bottom[value]
					else:
						layer = tex_side[value]
					_emit_face(surface, padded, i, f, lx, ly, lz, layer, stage, tint,
						is_slab, is_clear, opaque_flags)
	return {"opaque": opaque.to_arrays(), "transparent": clear.to_arrays()}


static func _face_visible(value: int, neighbour: int, f: int, is_slab: bool, is_clear: bool,
		opaque_flags: PackedByteArray, shape: PackedByteArray, solid: PackedByteArray) -> bool:
	if neighbour == 0:
		return true
	if neighbour == VoxelWorld.BOUNDARY:
		# Yuklenmemis komsu: yuzu CIZ. Aksi halde yuklenmemis chunk kenarinda
		# dunyanin "icine" bakilabilirdi. Komsu yuklenince yeniden meshlenir.
		return true
	if is_slab and f == 2:
		return true                      # yarim blogun ustu hep acik
	if opaque_flags[neighbour] == 1:
		return false
	if neighbour == value and is_clear:
		return false                     # cam-cam, su-su arasi yuz yok
	if f == 2 and shape[neighbour] == BlockMaterials.SHAPE_SLAB and solid[neighbour] == 1:
		return false                     # ustteki yarim blogun tabani ortuyor
	if is_clear and solid[value] == 0 and solid[neighbour] == 1 and opaque_flags[neighbour] == 0:
		return true
	return true


static func _tint(x: int, y: int, z: int) -> float:
	## Blok basina hafif ton farki: tekrar eden duz duvarlari canlandirir.
	var h := (x * 73856093) ^ (y * 19349663) ^ (z * 83492791)
	h = (h ^ (h >> 13)) & 0xFFFF
	return 0.9 + (h / 65535.0) * 0.12


static func _emit_face(surface: _Surface, padded: PackedByteArray, i: int, f: int,
		lx: int, ly: int, lz: int, layer: int, stage: int, tint: float,
		is_slab: bool, is_clear: bool, opaque_flags: PackedByteArray) -> void:
	var corners: Array = _corners[f]
	var ao_offsets: Array = _ao_offsets[f]
	var normal := Vector3(FACES[f].n)
	var base := surface.vertices.size()
	var ao := PackedFloat32Array([1.0, 1.0, 1.0, 1.0])
	var ao_level := PackedInt32Array([3, 3, 3, 3])
	var origin := Vector3(lx, ly, lz)
	for k in 4:
		var corner: Vector3 = corners[k]
		var offsets: Array = ao_offsets[k]
		var side1 := opaque_flags[padded[i + offsets[0]]] == 1
		var side2 := opaque_flags[padded[i + offsets[1]]] == 1
		var diag := opaque_flags[padded[i + offsets[2]]] == 1
		var level := 0 if (side1 and side2) else 3 - int(side1) - int(side2) - int(diag)
		if is_clear:
			level = 3
		ao_level[k] = level
		ao[k] = AO_LEVELS[level]
		var position := corner
		if is_slab:
			position.y *= 0.5
		surface.vertices.append(origin + position)
		surface.normals.append(normal)
		surface.uvs.append(_uv(f, position))
		surface.uv2s.append(Vector2(layer, stage))
		var shade := ao[k] * tint
		surface.colors.append(Color(shade, shade, shade, 1.0))
	# AO anizotropisi: koyu koseler karsilikli ise kosegeni cevir, aksi
	# halde dortgen uzerinde yapay bir "X" cizgisi gorunur.
	if ao_level[0] + ao_level[2] < ao_level[1] + ao_level[3]:
		surface.indices.append_array([base + 1, base + 2, base + 3, base + 1, base + 3, base])
	else:
		surface.indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])


static func _uv(f: int, p: Vector3) -> Vector2:
	match f:
		0: return Vector2(1.0 - p.z, 1.0 - p.y)
		1: return Vector2(p.z, 1.0 - p.y)
		2: return Vector2(p.x, p.z)
		3: return Vector2(p.x, 1.0 - p.z)
		4: return Vector2(p.x, 1.0 - p.y)
		_: return Vector2(1.0 - p.x, 1.0 - p.y)


class _Surface:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	func to_arrays() -> Variant:
		if vertices.is_empty():
			return null
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_TEX_UV2] = uv2s
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_INDEX] = indices
		return arrays
