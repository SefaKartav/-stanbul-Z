class_name VoxelTerrain
extends Node3D
## Voxel dunyasinin GORSEL tarafi: chunk uretimi, meshleme, akis.
##
## IS PARCACIGI KURALLARI
##   * Uretim ve meshleme WorkerThreadPool'da calisir; girdileri ana is
##     parcaciginda alinan KOPYALARDIR (uretimde bos yeni chunk, meshlemede
##     18^3 pay'li anlik goruntu). Isciler dunyaya asla yazmaz.
##   * Sonuclar ana is parcaciginda uygulanir. Meshleme sonucu, is
##     basladigindaki chunk SURUMU hala gecerliyse kullanilir; arada bir blok
##     kirildiysa sonuc atilir ve chunk yeniden kuyruga girer. Boylece
##     gecikmeli bir mesh yeni yikimi geri getiremez.
##   * Isin/carpisma sorgulari mesh'e degil VoxelWorld'e bakar; mesh gecikse
##     bile vurus hesabi guncel veriyi kullanir.

signal chunk_generated(coord: Vector3i)

var world: VoxelWorld
var generator: Object
var view_radius := 7                    # meshlenen yaricap (chunk)
var focus := Vector3.ZERO
var use_threads := true
var max_inflight_mesh := 6
var max_inflight_gen := 6
var apply_budget_usec := 4000
var snapshot_budget_usec := 3000

var opaque_material: ShaderMaterial
var clear_material: ShaderMaterial

var _min_chunk_y := -1
var _max_chunk_y := 6
var _meshes: Dictionary = {}           # coord -> [opaque MeshInstance3D, clear MeshInstance3D]
var _meshed: Dictionary = {}           # coord -> meshlenen surum
var _meshed_lod: Dictionary = {}       # coord -> meshlendigi ayrinti duzeyi (0 yakin, 1 uzak)
const LOD_NEAR := 3                    # chunk: bu yaricapta ic mekan yuzeyleri meshlenir
var _dirty: Dictionary = {}            # coord -> true
var _mesh_tasks: Dictionary = {}       # coord -> {id, version}
var _gen_tasks: Dictionary = {}        # coord -> {id, chunk}
var _mesh_results: Dictionary = {}     # coord -> sonuc (iscinin yazdigi)
var _mutex := Mutex.new()
var _needed: Array = []                # yaricaptaki chunk'lar, yakindan uzaga
var _focus_chunk := Vector3i(1 << 20, 0, 0)
var _fill_value := 0                   # dunya tabaninin altini doldurmak icin
var stats := {"generated": 0, "meshed": 0, "discarded": 0, "faces": 0,
	"last_mesh_usec": 0, "max_mesh_usec": 0}


func setup(p_world: VoxelWorld, p_generator: Object) -> void:
	world = p_world
	generator = p_generator
	world.generator = generator
	world.chunk_dirty.connect(_on_chunk_dirty)
	_min_chunk_y = world.min_cell.y >> VoxelWorld.SHIFT
	_max_chunk_y = (world.max_cell.y - 1) >> VoxelWorld.SHIFT
	_fill_value = world.materials.index_of("stone")
	ChunkMesher._prepare()
	_build_materials()


func _build_materials() -> void:
	var albedo := BlockTextures.build_array(world.materials.texture_ids)
	var cracks := BlockTextures.crack_array()
	opaque_material = ShaderMaterial.new()
	opaque_material.shader = load("res://src/voxel/voxel_opaque.gdshader")
	opaque_material.set_shader_parameter("albedo_tex", albedo)
	opaque_material.set_shader_parameter("crack_tex", cracks)
	clear_material = ShaderMaterial.new()
	clear_material.shader = load("res://src/voxel/voxel_clear.gdshader")
	clear_material.set_shader_parameter("albedo_tex", albedo)
	clear_material.set_shader_parameter("crack_tex", cracks)
	clear_material.render_priority = 1
	apply_look()
	if not Settings.changed.is_connected(apply_look):
		Settings.changed.connect(apply_look)


func apply_look() -> void:
	## Yumusak gorunum ayari (Ayarlar > Grafik): mat palet + uzak yumusatma.
	var soft := Settings.soft_look
	for material: ShaderMaterial in [opaque_material, clear_material]:
		if material != null:
			material.set_shader_parameter("matte", 1.0 if soft else 0.0)
			material.set_shader_parameter("distance_soften", 1.2 if soft else 0.0)


func set_view_radius(radius: int) -> void:
	## Oyun icinde gorus mesafesi degisimi: gerekli chunk listesi yeniden
	## kurulur, uzakta kalanlar bir sonraki tazelemede bosaltilir.
	view_radius = radius
	_focus_chunk = Vector3i(1 << 20, 0, 0)


func _exit_tree() -> void:
	# Havuzdaki her is beklenmeli; aksi halde kapanista kaynak sizar.
	for entry: Dictionary in _mesh_tasks.values():
		WorkerThreadPool.wait_for_task_completion(entry.id)
	for entry: Dictionary in _gen_tasks.values():
		WorkerThreadPool.wait_for_task_completion(entry.id)
	_mesh_tasks.clear()
	_gen_tasks.clear()


func _on_chunk_dirty(coord: Vector3i) -> void:
	if world.has_chunk(coord):
		_dirty[coord] = true


# --- ana dongu ---
func _process(_delta: float) -> void:
	if world == null:
		return
	update_step()


var last_step_usec := 0


func update_step() -> void:
	var t0 := Time.get_ticks_usec()
	_refresh_needed()
	_collect_generation()
	_dispatch_generation()
	_collect_meshes()
	_dispatch_meshes()
	last_step_usec = Time.get_ticks_usec() - t0


func update_sync(max_iterations: int = 100000) -> void:
	## Testler ve yukleme ekrani icin: yaricaptaki her sey hazir olana dek
	## bekler (is parcacigi kullanmadan).
	var previous := use_threads
	use_threads = false
	for _i in max_iterations:
		_refresh_needed()
		var before: int = stats.generated + stats.meshed
		_dispatch_generation()
		_dispatch_meshes()
		if stats.generated + stats.meshed == before and _dirty.is_empty():
			break
	use_threads = previous


func progress() -> float:
	## Yukleme ekrani icin: yaricaptaki chunk'larin ne kadari meshlendi.
	if _needed.is_empty():
		return 0.0
	var ready := 0
	var total := 0
	for coord: Vector3i in _needed:
		if not _in_mesh_radius(coord):
			continue
		total += 1
		if _meshed.has(coord):
			ready += 1
	return float(ready) / maxf(1.0, total)


func _refresh_needed() -> void:
	var fc := Vector3i(floori(focus.x) >> VoxelWorld.SHIFT, 0, floori(focus.z) >> VoxelWorld.SHIFT)
	if fc == _focus_chunk:
		return
	_focus_chunk = fc
	_needed.clear()
	# Uretim halkasi mesh halkasindan 2 chunk genis: kenardaki bir chunk'in
	# CAPRAZ komsusu sqrt(2) uzaktadir; +1 halka onu kacirir ve o chunk hic
	# meshlenmezdi (dairesel halkada koseler kalir).
	var r := view_radius + 2
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dz * dz > r * r:
				continue
			# Sutunun gokyuzu sinirinin ustu uretilmez (kesin hava).
			var top := mini(_max_chunk_y, world.top_chunk(fc.x + dx, fc.z + dz))
			for cy in range(_min_chunk_y, top + 1):
				var coord := Vector3i(fc.x + dx, cy, fc.z + dz)
				if not _column_in_world(coord):
					continue
				_needed.append(coord)
	_needed.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		return _dist2(a) < _dist2(b))
	_unload_far()


func _column_in_world(coord: Vector3i) -> bool:
	var x0 := coord.x * VoxelWorld.CHUNK
	var z0 := coord.z * VoxelWorld.CHUNK
	return x0 + VoxelWorld.CHUNK > world.min_cell.x and x0 < world.max_cell.x \
		and z0 + VoxelWorld.CHUNK > world.min_cell.z and z0 < world.max_cell.z


func _dist2(coord: Vector3i) -> int:
	var dx := coord.x - _focus_chunk.x
	var dz := coord.z - _focus_chunk.z
	return dx * dx + dz * dz


func _in_mesh_radius(coord: Vector3i) -> bool:
	var r := view_radius + 0.5
	return _dist2(coord) <= r * r


func _unload_far() -> void:
	var limit := (view_radius + 3) * (view_radius + 3)
	for coord: Vector3i in _meshes.keys():
		if _dist2(coord) > limit:
			_free_mesh(coord)
	for coord: Vector3i in world.chunks.keys():
		if _dist2(coord) > limit and not _mesh_tasks.has(coord):
			world.unload_chunk(coord)
			_dirty.erase(coord)
			_meshed.erase(coord)


# --- uretim ---
func _dispatch_generation() -> void:
	var started := Time.get_ticks_usec()
	for coord: Vector3i in _needed:
		if world.has_chunk(coord) or _gen_tasks.has(coord):
			continue
		if use_threads:
			if _gen_tasks.size() >= max_inflight_gen:
				return
			var chunk := VoxelChunk.new(coord)
			var id := WorkerThreadPool.add_task(_generate_task.bind(chunk), false, "voxel-uretim")
			_gen_tasks[coord] = {"id": id, "chunk": chunk}
		else:
			var generated := VoxelChunk.new(coord)
			if generator != null:
				generator.generate_chunk(generated)
			_adopt(generated)
			if Time.get_ticks_usec() - started > 200000:
				return


func _generate_task(chunk: VoxelChunk) -> void:
	if generator != null:
		generator.generate_chunk(chunk)


func _collect_generation() -> void:
	for coord: Vector3i in _gen_tasks.keys():
		var entry: Dictionary = _gen_tasks[coord]
		if not WorkerThreadPool.is_task_completed(entry.id):
			continue
		WorkerThreadPool.wait_for_task_completion(entry.id)
		_gen_tasks.erase(coord)
		if not world.has_chunk(coord):
			_adopt(entry.chunk)


func _adopt(chunk: VoxelChunk) -> void:
	world.adopt_chunk(chunk)
	stats.generated += 1
	chunk_generated.emit(chunk.coord)


# --- meshleme ---
func _neighbours_ready(coord: Vector3i) -> bool:
	for dy in [-1, 0, 1]:
		var cy: int = coord.y + dy
		if cy < _min_chunk_y or cy > _max_chunk_y:
			continue
		for dz in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				var n := Vector3i(coord.x + dx, cy, coord.z + dz)
				if not world.has_chunk(n) and _column_in_world(n) and not world.is_sky(n):
					return false
	return true


func _dispatch_meshes() -> void:
	var started := Time.get_ticks_usec()
	for coord: Vector3i in _needed:
		if not _in_mesh_radius(coord):
			continue
		var chunk: VoxelChunk = world.get_chunk(coord)
		if chunk == null or _mesh_tasks.has(coord):
			continue
		var lod := 0 if _dist2(coord) <= LOD_NEAR * LOD_NEAR else 1
		if _meshed.has(coord) and not _dirty.has(coord) and int(_meshed_lod.get(coord, 0)) == lod:
			continue
		if not _neighbours_ready(coord):
			continue
		if use_threads and _mesh_tasks.size() >= max_inflight_mesh:
			return
		_dirty.erase(coord)
		if chunk.is_empty():
			_free_mesh(coord)
			_meshed[coord] = chunk.version
			_meshed_lod[coord] = lod
			stats.meshed += 1
			continue
		var padded := _snapshot(coord)
		var stages := _stages_for(coord)
		var version := chunk.version
		if use_threads:
			var id := WorkerThreadPool.add_task(
				_mesh_task.bind(coord, padded, stages, chunk.origin(), version, lod), false, "voxel-mesh")
			_mesh_tasks[coord] = {"id": id, "version": version}
		else:
			var result := ChunkMesher.build(padded, stages, chunk.origin(), world.materials, lod)
			result["lod"] = lod
			_apply_mesh(coord, version, result)
		if Time.get_ticks_usec() - started > snapshot_budget_usec and use_threads:
			return


func _mesh_task(coord: Vector3i, padded: PackedByteArray, stages: Dictionary,
		chunk_origin: Vector3i, version: int, lod: int = 0) -> void:
	var t0 := Time.get_ticks_usec()
	var result := ChunkMesher.build(padded, stages, chunk_origin, world.materials, lod)
	result["lod"] = lod
	result["usec"] = Time.get_ticks_usec() - t0
	_mutex.lock()
	_mesh_results[coord] = result
	_mutex.unlock()


func _collect_meshes() -> void:
	var started := Time.get_ticks_usec()
	for coord: Vector3i in _mesh_tasks.keys():
		var entry: Dictionary = _mesh_tasks[coord]
		if not WorkerThreadPool.is_task_completed(entry.id):
			continue
		WorkerThreadPool.wait_for_task_completion(entry.id)
		_mesh_tasks.erase(coord)
		_mutex.lock()
		var result: Dictionary = _mesh_results.get(coord, {})
		_mesh_results.erase(coord)
		_mutex.unlock()
		_apply_mesh(coord, entry.version, result)
		if Time.get_ticks_usec() - started > apply_budget_usec:
			return


func _apply_mesh(coord: Vector3i, version: int, result: Dictionary) -> void:
	var chunk: VoxelChunk = world.get_chunk(coord)
	if chunk == null:
		return
	if chunk.version != version:
		# Is surerken blok degisti: bu sonuc artik yanlis. At ve yeniden kuyruga al.
		stats.discarded += 1
		_dirty[coord] = true
		return
	if result.has("usec"):
		stats.last_mesh_usec = result.usec
		stats.max_mesh_usec = maxi(stats.max_mesh_usec, result.usec)
	var nodes: Array = _meshes.get(coord, [])
	if nodes.is_empty():
		var opaque_node := MeshInstance3D.new()
		opaque_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		var clear_node := MeshInstance3D.new()
		clear_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(opaque_node)
		add_child(clear_node)
		var position := Vector3(chunk.origin())
		opaque_node.position = position
		clear_node.position = position
		nodes = [opaque_node, clear_node]
		_meshes[coord] = nodes
	_set_surface(nodes[0], result.get("opaque"), opaque_material)
	_set_surface(nodes[1], result.get("transparent"), clear_material)
	_meshed[coord] = version
	_meshed_lod[coord] = int(result.get("lod", 0))
	stats.meshed += 1


func _set_surface(node: MeshInstance3D, arrays: Variant, material: Material) -> void:
	if arrays == null:
		node.mesh = null
		return
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	node.mesh = mesh


func _free_mesh(coord: Vector3i) -> void:
	var nodes: Array = _meshes.get(coord, [])
	for node: Node in nodes:
		node.queue_free()
	_meshes.erase(coord)
	_meshed.erase(coord)
	_meshed_lod.erase(coord)


func _snapshot(coord: Vector3i) -> PackedByteArray:
	## Chunk + 1 hucrelik komsu payi (18^3). Isci bu KOPYAYI okur.
	var padded := PackedByteArray()
	padded.resize(ChunkMesher.P * ChunkMesher.P * ChunkMesher.P)
	var origin := coord * VoxelWorld.CHUNK
	var chunk: VoxelChunk = world.get_chunk(coord)
	var blocks := chunk.blocks
	# Govde: dogrudan kopya.
	for ly in 16:
		for lz in 16:
			var src := (ly * 16 + lz) * 16
			var dst := ((ly + 1) * ChunkMesher.P + (lz + 1)) * ChunkMesher.P + 1
			for lx in 16:
				padded[dst + lx] = blocks[src + lx]
	# Kenarlar: dunyadan oku.
	for y in range(-1, 17):
		for z in range(-1, 17):
			for x in range(-1, 17):
				if x >= 0 and x < 16 and y >= 0 and y < 16 and z >= 0 and z < 16:
					continue
				var wy := origin.y + y
				var value: int
				if wy < world.min_cell.y:
					value = _fill_value     # dunya tabani: gizli yuz cizme
				else:
					value = world.get_visual_block(origin.x + x, wy, origin.z + z)
				padded[((y + 1) * ChunkMesher.P + (z + 1)) * ChunkMesher.P + (x + 1)] = value
	return padded


func _stages_for(coord: Vector3i) -> Dictionary:
	var stages := {}
	if world.damage.is_empty():
		return stages
	var origin := coord * VoxelWorld.CHUNK
	for cell: Vector3i in world.damage:
		if VoxelWorld.chunk_of(cell) != coord:
			continue
		var stage := world.damage_stage(cell)
		if stage > 0:
			var l := cell - origin
			stages[(l.y * 16 + l.z) * 16 + l.x] = stage
	return stages


func mesh_node_count() -> int:
	return _meshes.size()
