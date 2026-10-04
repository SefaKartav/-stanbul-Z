class_name BuildingRegistry
extends RefCounted
## Binalarin KIMLIGI (OSM ayak izi, w<osm_id>) ve SINIFI.
##
## Bina artik bir loot envanteri DEGILDIR: arama, icerideki mobilya basina
## yapilir (bkz. ContainerRegistry, SearchSystem). Kimlik; us kurma (bina
## rolleri), harita katmanlari, hayatta kalan yerlesimi ve container
## kimliklerinin on eki icin korunur. Eski (v1) bina arama haklari kayit
## gocunde container durumuna cevrilir (ContainerRegistry.migrate_v1).

var generator: CityGenerator
var containers: ContainerRegistry


func _init(p_generator: CityGenerator) -> void:
	generator = p_generator


func count() -> int:
	return 0 if generator == null else generator.buildings.size()


func get_building(index: int) -> Dictionary:
	return generator.buildings[index]


func definition(index: int) -> BuildingClass:
	return Content.building_class(generator.buildings[index].class)


func at_cell(cell: Vector3i) -> int:
	## Bu hucre hangi binanin ayak izinde? (yuzey malzemesine bakilmaz)
	if generator == null:
		return -1
	var index := generator.building_at(cell.x, cell.z)
	if index < 0:
		return -1
	var b: Dictionary = generator.buildings[index]
	if cell.y < b.base_y - 3 or cell.y > b.top_y + 2:
		return -1
	return index


func area_m2(index: int) -> float:
	return CityGenerator._poly_area(generator.buildings[index].poly)


func is_touched(index: int) -> bool:
	## Icinde en az bir mobilya arandi mi? (harita "aranmamis" katmani)
	return containers != null and containers.building_clock.has(generator.buildings[index].id)
