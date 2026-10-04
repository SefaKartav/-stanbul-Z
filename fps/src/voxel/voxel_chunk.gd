class_name VoxelChunk
extends RefCounted
## 16x16x16 hucrelik mantiksal blok verisi.
##
## Her hucre TEK BAYT: malzeme indeksi (0 = hava). Bir chunk 4 KB'tir;
## oynanabilir alanin tamami birkac megabayta sigar. Gorsel mesh bu veriden
## TURETILIR ve asla kaynak degildir: mermi, carpisma, gorus ve AI hep
## buraya bakar. "Cizilen sey ile vurulan sey farkli" turu hatalar bu
## yuzden yapisal olarak olusamaz.

const SIZE := 16
const SHIFT := 4
const MASK := 15
const VOLUME := SIZE * SIZE * SIZE

var coord: Vector3i
var blocks := PackedByteArray()
# Her degisiklikte artar. Arka planda meshlenen sonuc, meshleme basladiginda
# okunan surumle ayni degilse ATILIR: eski bir mesh yeni yikimi geri getiremez.
var version := 0
var solid_count := 0      # hic dolu hucre yoksa meshleme atlanir


func _init(p_coord: Vector3i) -> void:
	coord = p_coord
	blocks.resize(VOLUME)


static func index(lx: int, ly: int, lz: int) -> int:
	return (ly * SIZE + lz) * SIZE + lx


func get_local(lx: int, ly: int, lz: int) -> int:
	return blocks[(ly * SIZE + lz) * SIZE + lx]


func set_local(lx: int, ly: int, lz: int, material: int) -> void:
	var i := (ly * SIZE + lz) * SIZE + lx
	var previous := blocks[i]
	if previous == material:
		return
	if previous == 0:
		solid_count += 1
	elif material == 0:
		solid_count -= 1
	blocks[i] = material
	version += 1


func recount() -> void:
	solid_count = 0
	for value in blocks:
		if value != 0:
			solid_count += 1


func is_empty() -> bool:
	return solid_count == 0


func origin() -> Vector3i:
	return coord * SIZE
