class_name VoxelWorld
extends RefCounted
## Mantiksal voxel dunyasi: tek dogruluk kaynagi.
##
## SAKLAMA STRATEJISI (belgenin 9. bolumu)
##   * Dunya tohumdan ve harita verisinden URETILIR; kayit dosyasina uretilmis
##     bloklar yazilmaz, yalnizca FARKLAR: kirilan, yerlestirilen, degisen.
##   * Hasarsiz blogun HP'si malzemeden turetilir; yalnizca HASARLI hucrelerin
##     kalan HP'si tutulur. Bir mahallenin milyonlarca hucresi icin nesne
##     yoktur -- oyuncu kac blogu vurduysa o kadar kayit vardir.
##   * Bir chunk bosaltilip yeniden uretildiginde farklar yeniden uygulanir;
##     yani chunk'i birakip geri gelmek ya da oyunu kapatmak dunyayi ONARMAZ.
##
## BILINMEYEN = DUVAR
##   Uretilmemis bir chunk'a ya da harita sinirinin disina bakan her sorgu
##   `BOUNDARY` doner ve kati sayilir. Belgenin istedigi gibi: yuklenmemis
##   bolge icinden ates edilebilir hava DEGILDIR, oyuncu da oraya dusmez.

signal block_changed(cell: Vector3i, previous: int, current: int)
signal chunk_dirty(coord: Vector3i)

const CHUNK := VoxelChunk.SIZE
const SHIFT := VoxelChunk.SHIFT
const MASK := VoxelChunk.MASK
const BOUNDARY := 255
# Hasar gorselinin kac kademesi var (0 = saglam). Kademe degismedikce
# chunk yeniden meshlenmez: her mermide meshlemek israf olurdu.
const DAMAGE_STAGES := 4

# Kaynak kokeni: bir hucredeki blogun nereden geldigi.
const ORIGIN_WORLD := 0      # haritanin kendisi (kurtarma dususu verebilir)
const ORIGIN_PLACED := 1     # oyuncu/koloni koydu (dusus YOK -- cogaltma engeli)

var materials: BlockMaterials
var generator: Object = null           # generate_chunk(chunk: VoxelChunk) -> void
var chunks: Dictionary = {}            # Vector3i -> VoxelChunk
var min_cell := Vector3i(-100000, -32, -100000)
var max_cell := Vector3i(100000, 160, 100000)   # dahil degil

# --- farklar (kaydedilen durum) ---
var modified: Dictionary = {}          # Vector3i hucre -> malzeme indeksi (0 = kirildi)
var mods_by_chunk: Dictionary = {}     # Vector3i chunk -> {Vector3i hucre: true}
var placed: Dictionary = {}            # Vector3i hucre -> true (oyuncu kokenli)
var damage: Dictionary = {}            # Vector3i hucre -> kalan hp

var _last_coord := Vector3i(1 << 30, 0, 0)
var _last_chunk: VoxelChunk = null

# --- sutun basina gokyuzu siniri ---
# column_top(cx, cz) -> bu chunk sutununda uretilen en yuksek chunk katmani.
# Ustundeki chunk'lar URETILMEZ ve KESIN HAVADIR (uretici oyle garanti eder).
# "Bilinmeyen = duvar" kurali bunun altinda aynen gecerlidir. Dikey sinir
# dinamik oldugu icin 40 katli bina sutununda 10+ chunk, bos sokakta 3 chunk.
var column_top: Callable
var _tops: Dictionary = {}             # Vector2i -> int (yalnizca ana is parcacigi)

# --- girilebilir alan maskesi (koridor haritasi) ---
# Maskede 0 olan sutunlar sorgulara BOUNDARY doner: oyuncu, zombi, arac ve
# mermi icin gorunmez duvar. Chunk verisi ise GERCEKTIR ve meshlenir; yani
# sinir disi, ufukta sise karisan manzara olarak gorulur ama girilemez.
var _limit := PackedByteArray()
var _limit_shift := 0
var _limit_w := 0
var _limited := false


func _init(p_materials: BlockMaterials) -> void:
	materials = p_materials


func set_limit(mask: PackedByteArray, cell_shift: int, mask_width: int) -> void:
	## mask: (z >> shift) * genislik + (x >> shift) -> 1 girilebilir, 0 sinir.
	_limit = mask
	_limit_shift = cell_shift
	_limit_w = mask_width
	_limited = not mask.is_empty()


func is_open_column(x: int, z: int) -> bool:
	## Sutun oynanabilir alanda mi? (harita siniri + koridor maskesi)
	if x < min_cell.x or x >= max_cell.x or z < min_cell.z or z >= max_cell.z:
		return false
	if not _limited:
		return true
	var i := (z >> _limit_shift) * _limit_w + (x >> _limit_shift)
	return i >= 0 and i < _limit.size() and _limit[i] != 0


# --- koordinatlar ---
static func chunk_of(cell: Vector3i) -> Vector3i:
	return Vector3i(cell.x >> SHIFT, cell.y >> SHIFT, cell.z >> SHIFT)


static func cell_of(position: Vector3) -> Vector3i:
	return Vector3i(floori(position.x), floori(position.y), floori(position.z))


func in_bounds(cell: Vector3i) -> bool:
	return cell.x >= min_cell.x and cell.y >= min_cell.y and cell.z >= min_cell.z \
		and cell.x < max_cell.x and cell.y < max_cell.y and cell.z < max_cell.z


# --- chunk yonetimi ---
func get_chunk(coord: Vector3i) -> VoxelChunk:
	return chunks.get(coord)


func has_chunk(coord: Vector3i) -> bool:
	return chunks.has(coord)


func ensure_chunk(coord: Vector3i) -> VoxelChunk:
	## Chunk yoksa uretir ve kayitli farklari uygular.
	var chunk: VoxelChunk = chunks.get(coord)
	if chunk != null:
		return chunk
	chunk = VoxelChunk.new(coord)
	if generator != null:
		generator.generate_chunk(chunk)
	adopt_chunk(chunk)
	return chunk


func adopt_chunk(chunk: VoxelChunk) -> void:
	## Baska yerde (ornegin arka plan is parcaciginda) uretilmis chunk'i
	## dunyaya alir ve kayitli farklari uzerine uygular.
	_apply_modifications(chunk)
	chunk.recount()
	chunks[chunk.coord] = chunk
	_last_coord = Vector3i(1 << 30, 0, 0)
	_last_chunk = null


func unload_chunk(coord: Vector3i) -> void:
	## Veriyi bellekten atar. Farklar `modified` icinde kaldigi icin geri
	## yuklendiginde dunya ayni gorunur.
	chunks.erase(coord)
	_last_coord = Vector3i(1 << 30, 0, 0)
	_last_chunk = null


func _apply_modifications(chunk: VoxelChunk) -> void:
	var cells: Dictionary = mods_by_chunk.get(chunk.coord, {})
	for cell: Vector3i in cells:
		chunk.blocks[VoxelChunk.index(cell.x & MASK, cell.y & MASK, cell.z & MASK)] = modified[cell]


# --- okuma ---
func get_block(x: int, y: int, z: int) -> int:
	if y < min_cell.y or y >= max_cell.y or x < min_cell.x or x >= max_cell.x \
			or z < min_cell.z or z >= max_cell.z:
		return BOUNDARY
	if _limited:
		var li := (z >> _limit_shift) * _limit_w + (x >> _limit_shift)
		if li >= _limit.size() or _limit[li] == 0:
			return BOUNDARY
	var coord := Vector3i(x >> SHIFT, y >> SHIFT, z >> SHIFT)
	if coord != _last_coord:
		_last_chunk = chunks.get(coord)
		_last_coord = coord
	if _last_chunk == null:
		return 0 if is_sky(coord) else BOUNDARY
	return _last_chunk.blocks[((y & MASK) * CHUNK + (z & MASK)) * CHUNK + (x & MASK)]


func top_chunk(cx: int, cz: int) -> int:
	## Sutunda uretilen en yuksek chunk katmani (gokyuzu siniri yoksa dunya tavani).
	if not column_top.is_valid():
		return (max_cell.y - 1) >> SHIFT
	var key := Vector2i(cx, cz)
	var cached: Variant = _tops.get(key)
	if cached == null:
		cached = mini(int(column_top.call(cx, cz)), (max_cell.y - 1) >> SHIFT)
		if _tops.size() > 200000:
			_tops.clear()
		_tops[key] = cached
	return cached


func is_sky(coord: Vector3i) -> bool:
	## Bu chunk uretici garantisiyle bos gokyuzu mu? (uretilmez, hava)
	return column_top.is_valid() and coord.y > top_chunk(coord.x, coord.z)


func get_visual_block(x: int, y: int, z: int) -> int:
	## Meshleme icin: girilebilir alan maskesini YOK SAYAR. Manzara seridindeki
	## chunk kenarlarinda gereksiz (toprak icinde kalan) yuz uretilmesin.
	if y < min_cell.y or y >= max_cell.y or x < min_cell.x or x >= max_cell.x \
			or z < min_cell.z or z >= max_cell.z:
		return BOUNDARY
	var coord := Vector3i(x >> SHIFT, y >> SHIFT, z >> SHIFT)
	var chunk: VoxelChunk = chunks.get(coord)
	if chunk == null:
		return 0 if is_sky(coord) else BOUNDARY
	return chunk.blocks[((y & MASK) * CHUNK + (z & MASK)) * CHUNK + (x & MASK)]


func get_cell(cell: Vector3i) -> int:
	return get_block(cell.x, cell.y, cell.z)


func is_solid(x: int, y: int, z: int) -> bool:
	var value := get_block(x, y, z)
	return value == BOUNDARY or (value != 0 and materials.solid[value] == 1)


func cell_height(value: int) -> float:
	## Hucrenin carpisma yuksekligi (0 = bos). Sinir ve bilinmeyen tam blok.
	if value == 0:
		return 0.0
	if value == BOUNDARY:
		return 1.0
	if materials.solid[value] == 0:
		return 0.0
	return 0.5 if materials.shape[value] == BlockMaterials.SHAPE_SLAB else 1.0


# --- yazma ---
func set_block(cell: Vector3i, material: int, origin: int = ORIGIN_PLACED) -> bool:
	## Bir hucreyi degistirir ve FARK olarak kaydeder. Uretilmemis chunk'a
	## yazilamaz: gormedigin yere blok koymak/kirmak yok.
	if not in_bounds(cell):
		return false
	var coord := chunk_of(cell)
	var chunk: VoxelChunk = chunks.get(coord)
	if chunk == null:
		return false
	var local := VoxelChunk.index(cell.x & MASK, cell.y & MASK, cell.z & MASK)
	var previous := chunk.blocks[local]
	if previous == material:
		return false
	chunk.set_local(cell.x & MASK, cell.y & MASK, cell.z & MASK, material)
	modified[cell] = material
	if not mods_by_chunk.has(coord):
		mods_by_chunk[coord] = {}
	mods_by_chunk[coord][cell] = true
	damage.erase(cell)
	if material != 0 and origin == ORIGIN_PLACED:
		placed[cell] = true
	else:
		placed.erase(cell)
	_mark_dirty(cell, coord)
	block_changed.emit(cell, previous, material)
	return true


func _mark_dirty(cell: Vector3i, coord: Vector3i) -> void:
	## Hucre chunk kenarindaysa KOMSU chunk da yeniden meshlenmeli; aksi
	## halde kenarda "gorunmez delik" ya da "havada asili yuz" kalir.
	chunk_dirty.emit(coord)
	var lx := cell.x & MASK
	var ly := cell.y & MASK
	var lz := cell.z & MASK
	if lx == 0: chunk_dirty.emit(coord + Vector3i(-1, 0, 0))
	if lx == MASK: chunk_dirty.emit(coord + Vector3i(1, 0, 0))
	if ly == 0: chunk_dirty.emit(coord + Vector3i(0, -1, 0))
	if ly == MASK: chunk_dirty.emit(coord + Vector3i(0, 1, 0))
	if lz == 0: chunk_dirty.emit(coord + Vector3i(0, 0, -1))
	if lz == MASK: chunk_dirty.emit(coord + Vector3i(0, 0, 1))


# --- hasar ---
func hp_of(cell: Vector3i) -> float:
	var value := get_cell(cell)
	if value == 0 or value == BOUNDARY:
		return 0.0
	return float(damage.get(cell, materials.max_hp[value]))


func damage_stage(cell: Vector3i) -> int:
	## 0 = saglam .. DAMAGE_STAGES-1 = kirilmak uzere.
	if not damage.has(cell):
		return 0
	var value := get_cell(cell)
	if value == 0 or value == BOUNDARY:
		return 0
	var ratio := 1.0 - float(damage[cell]) / maxf(1.0, materials.max_hp[value])
	return clampi(int(ratio * DAMAGE_STAGES), 0, DAMAGE_STAGES - 1)


func apply_damage(cell: Vector3i, amount: float) -> Dictionary:
	## Hucreye HAM hasar uygular (carpanlar cagirana aittir). Sonuc:
	## {material, destroyed, hp, dealt}. Sinir ve sivi hasar almaz.
	var result := {"material": 0, "destroyed": false, "hp": 0.0, "dealt": 0.0, "origin": ORIGIN_WORLD}
	var value := get_cell(cell)
	if value == 0 or value == BOUNDARY or materials.solid[value] == 0 or amount <= 0.0:
		return result
	result.material = value
	result.origin = ORIGIN_PLACED if placed.has(cell) else ORIGIN_WORLD
	var hp := hp_of(cell)
	var before_stage := damage_stage(cell)
	var left := hp - amount
	result.dealt = minf(hp, amount)
	if left <= 0.0:
		result.destroyed = true
		# Kirilan hucre HAVA olur ve hemen etkilidir: bir sonraki isin,
		# carpisma ve yol bulma sorgusu bosluk gorur. Gorunmez duvar kalmaz.
		set_block(cell, 0, ORIGIN_WORLD)
		return result
	damage[cell] = left
	result.hp = left
	if damage_stage(cell) != before_stage:
		# Yalnizca gorsel kademe degisince yeniden meshle.
		var chunk: VoxelChunk = chunks.get(chunk_of(cell))
		if chunk != null:
			chunk.version += 1
		chunk_dirty.emit(chunk_of(cell))
	return result


func repair(cell: Vector3i, amount: float) -> float:
	## Hasarli blogu onarir; onarilan HP'yi dondurur.
	if not damage.has(cell):
		return 0.0
	var value := get_cell(cell)
	if value == 0 or value == BOUNDARY:
		damage.erase(cell)
		return 0.0
	var maximum := materials.max_hp[value]
	var before: float = damage[cell]
	var after := minf(maximum, before + amount)
	var stage_before := damage_stage(cell)
	if after >= maximum:
		damage.erase(cell)
	else:
		damage[cell] = after
	if damage_stage(cell) != stage_before:
		var chunk: VoxelChunk = chunks.get(chunk_of(cell))
		if chunk != null:
			chunk.version += 1
		chunk_dirty.emit(chunk_of(cell))
	return after - before


# --- kalicilik ---
func to_dict() -> Dictionary:
	## Farklar kompakt dizi olarak yazilir: [x, y, z, malzeme, koken].
	var mods: Array = []
	for cell: Vector3i in modified:
		mods.append([cell.x, cell.y, cell.z, modified[cell], 1 if placed.has(cell) else 0])
	var hurt: Array = []
	for cell: Vector3i in damage:
		hurt.append([cell.x, cell.y, cell.z, snappedf(damage[cell], 0.1)])
	return {"modified": mods, "damage": hurt}


func load_dict(data: Dictionary) -> void:
	modified.clear()
	mods_by_chunk.clear()
	placed.clear()
	damage.clear()
	for entry: Variant in data.get("modified", []):
		if typeof(entry) != TYPE_ARRAY or entry.size() < 4:
			continue
		var cell := Vector3i(int(entry[0]), int(entry[1]), int(entry[2]))
		var material := int(entry[3])
		if material < 0 or material > 254 or (material != 0 and materials.by_index[material] == null):
			continue
		modified[cell] = material
		var coord := chunk_of(cell)
		if not mods_by_chunk.has(coord):
			mods_by_chunk[coord] = {}
		mods_by_chunk[coord][cell] = true
		if entry.size() > 4 and int(entry[4]) == 1 and material != 0:
			placed[cell] = true
	for entry: Variant in data.get("damage", []):
		if typeof(entry) == TYPE_ARRAY and entry.size() >= 4:
			damage[Vector3i(int(entry[0]), int(entry[1]), int(entry[2]))] = float(entry[3])
	# Yuklu chunk'lari farklarla yeniden kur: eski oturumun blok durumu
	# bellekte kalmamali.
	var coords := chunks.keys()
	chunks.clear()
	_last_coord = Vector3i(1 << 30, 0, 0)
	_last_chunk = null
	for coord: Vector3i in coords:
		ensure_chunk(coord)
		chunk_dirty.emit(coord)
