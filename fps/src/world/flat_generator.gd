class_name FlatGenerator
extends RefCounted
## En basit uretici: y < 0 toprak/tas, ustu hava. Testler ve teshis icin.
## Is parcacigi guvenlidir: yalnizca kendi alanlarini okur.

var ground: int
var subsoil: int
var ground_level := 0


func _init(materials: BlockMaterials) -> void:
	ground = materials.index_of("grass")
	subsoil = materials.index_of("dirt")


func generate_chunk(chunk: VoxelChunk) -> void:
	var origin := chunk.origin()
	for ly in VoxelChunk.SIZE:
		var y := origin.y + ly
		if y >= ground_level:
			break
		var value := ground if y == ground_level - 1 else subsoil
		for lz in VoxelChunk.SIZE:
			for lx in VoxelChunk.SIZE:
				chunk.blocks[VoxelChunk.index(lx, ly, lz)] = value
