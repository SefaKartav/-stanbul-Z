extends Node
## Arac kurallari: blok kirmaz, guvenli inis, yakit gercek esyadan; surus
## fizigi (bordur, duvar, tunelleme, yuklenmemis chunk, geri vites, hizli inis).

const DT := 1.0 / 60.0


func _m(id: String) -> int:
	return Content.blocks.index_of(id)


func _setup(chunk_range: int = 3) -> Array:
	var world := VoxelWorld.new(Content.blocks)
	world.generator = FlatGenerator.new(Content.blocks)
	world.min_cell = Vector3i(-64, -16, -64)
	world.max_cell = Vector3i(64, 48, 64)
	for cy in range(-1, 2):
		for cz in range(-chunk_range, chunk_range):
			for cx in range(-chunk_range, chunk_range):
				world.ensure_chunk(Vector3i(cx, cy, cz))
	var vehicles := Vehicles.new()
	add_child(vehicles)
	vehicles.setup(world, ActorRegistry.new())
	return [world, vehicles]


static func _noise(_p: Vector3, _r: float) -> void:
	pass


func _row(world: VoxelWorld, z: int, material: String, height: int = 1, x0: int = -6, x1: int = 7) -> void:
	for x in range(x0, x1):
		for y in height:
			world.set_block(Vector3i(x, y, z), _m(material), VoxelWorld.ORIGIN_WORLD)


func _drive(vehicles: Vehicles, frames: int, throttle: float, steer: float = 0.0, brake: bool = false, dt: float = DT) -> void:
	for _i in frames:
		vehicles.drive(dt, throttle, steer, brake, _noise)


func test_crash_stops_car_and_breaks_no_block(t) -> void:
	var s := _setup()
	var world: VoxelWorld = s[0]
	var vehicles: Vehicles = s[1]
	for z in range(-12, -9):
		_row(world, z, "wood", 3, -4, 5)
	var before := world.modified.size()
	var car := vehicles._create("sedan", "sedan", Vector3(0.5, 0.0, 0.5), 0.0)   # -Z yonune bakar
	car.fuel = 20.0
	vehicles.enter(car)
	_drive(vehicles, 240, 1.0)
	var nose: float = car.position.z - float(car.half_l)
	t.ok(nose > -9.0 - 0.05, "arac burnu duvara girmemeli (burun z=%.2f)" % nose)
	t.eq(world.modified.size(), before, "arac carpmasi blok kirmamali")
	t.ok(car.durability < float(Vehicles.def_of(car).durability), "carpma araci hasarlamali")
	vehicles.queue_free()


func test_collision_uses_real_length_and_width(t) -> void:
	## Sedan 2 m genis, 4.1 m uzun: 1.6 m yandaki direk degmez, 1.8 m
	## ondeki direk degmeli (eskiden hepsi 2.1 m'lik kareydi).
	var s := _setup()
	var world: VoxelWorld = s[0]
	var vehicles: Vehicles = s[1]
	var car := vehicles._create("sedan", "sedan", Vector3(0.5, 0.0, 0.5), 0.0)
	t.ok(float(car.half_l) > float(car.half_w) + 0.6, "uzunluk genislikten belirgin buyuk (%.2f / %.2f)" % [car.half_l, car.half_w])
	world.set_block(Vector3i(2, 0, 0), _m("brick"), VoxelWorld.ORIGIN_WORLD)     # yanda, x 2..3
	t.ok(vehicles._try_place(car, car.position, 0.0).ok, "yandaki direk (1.5 m) govdeye degmez")
	world.set_block(Vector3i(0, 0, -2), _m("brick"), VoxelWorld.ORIGIN_WORLD)    # onde, z -2..-1
	t.ok(not vehicles._try_place(car, car.position, 0.0).ok, "burun hizasindaki direk carpar")
	# 90 derece donuk: burun artik +-X'e bakar, yandaki direk (x 2..3) carpar.
	world.set_block(Vector3i(0, 0, -2), 0, VoxelWorld.ORIGIN_WORLD)
	t.ok(not vehicles._try_place(car, car.position, PI * 0.5).ok, "donuk govde yonlendirilmis kutuyla carpar")
	vehicles.queue_free()


func test_curb_is_climbed_but_wall_is_not(t) -> void:
	## Yarim blok bordur (0.5 m) asilir; tam blok (1 m) duvar asilmaz --
	## basamak toleransi tirmanma yetenegine donusmemeli.
	var s := _setup()
	var world: VoxelWorld = s[0]
	var vehicles: Vehicles = s[1]
	for z in range(-40, -4):
		_row(world, z, "sidewalk")
	var car := vehicles._create("sedan", "sedan", Vector3(0.5, 0.0, 0.5), 0.0)
	car.fuel = 20.0
	vehicles.enter(car)
	_drive(vehicles, 120, 0.6)
	t.ok(car.position.z < -8.0, "bordura cikilmali (z=%.2f)" % car.position.z)
	t.ok(absf(car.position.y - 0.5) < 0.06, "kaldirim ustunde 0.5 m'de durmali (y=%.2f)" % car.position.y)
	vehicles.queue_free()
	# Yol seviyesinde tek bloklik (1 m) duvar / kum torbasi: gecilmez.
	s = _setup()
	world = s[0]
	vehicles = s[1]
	_row(world, -12, "brick", 1)
	car = vehicles._create("sedan", "sedan", Vector3(0.5, 0.0, 0.5), 0.0)
	car.fuel = 20.0
	vehicles.enter(car)
	_drive(vehicles, 400, 0.6)
	t.ok(car.position.z - float(car.half_l) > -11.05, "1 m'lik duvara tirmanilmamali (z=%.2f)" % car.position.z)
	t.ok(car.position.y < 0.1, "arac duvarin ustune cikmamali (y=%.2f)" % car.position.y)
	vehicles.queue_free()


func test_half_block_slope_is_driven_up(t) -> void:
	## Arazi egimi 0.5 m'lik adimlarla yukselir (asfalt egim bloklari): arac
	## takilmadan cikar -- kopru yaklasimi ve yokuslar bu yuzden surulebilir.
	var s := _setup()
	var world: VoxelWorld = s[0]
	var vehicles: Vehicles = s[1]
	for step in 8:
		var z0 := -6 - step * 3
		for z in range(z0 - 2, z0 + 1):
			for x in range(-6, 7):
				for y in step / 2:
					world.set_block(Vector3i(x, y, z), _m("asphalt"), VoxelWorld.ORIGIN_WORLD)
				if step % 2 == 1:
					world.set_block(Vector3i(x, step / 2, z), _m("asphalt_half"), VoxelWorld.ORIGIN_WORLD)
	for z in range(-40, -29):
		for x in range(-6, 7):
			for y in 4:
				world.set_block(Vector3i(x, y, z), _m("asphalt"), VoxelWorld.ORIGIN_WORLD)
	var car := vehicles._create("sedan", "sedan", Vector3(0.5, 0.0, 0.5), 0.0)
	car.fuel = 20.0
	vehicles.enter(car)
	var top := 0.0
	for _i in 360:
		vehicles.drive(DT, 0.7, 0.0, false, _noise)
		top = maxf(top, car.position.y)
		if car.position.z < -33.0:
			break
	t.ok(top > 3.9, "yokusun ustune (4 m) cikilmali (en yuksek y=%.2f z=%.2f)" % [top, car.position.z])
	vehicles.queue_free()


func test_high_speed_does_not_tunnel(t) -> void:
	## Buyuk kare suresi + yuksek hiz: 1 blok kalinliginda duvarin otesine atlanmaz.
	var s := _setup()
	var world: VoxelWorld = s[0]
	var vehicles: Vehicles = s[1]
	_row(world, -20, "brick", 3)
	var car := vehicles._create("sedan", "sedan", Vector3(0.5, 0.0, 0.5), 0.0)
	car.fuel = 20.0
	vehicles.enter(car)
	car.speed = 35.0
	_drive(vehicles, 30, 1.0, 0.0, false, 0.1)
	t.ok(car.position.z > -19.0 + float(car.half_l) - 0.05, "duvarin otesine gecilmemeli (z=%.2f)" % car.position.z)
	vehicles.queue_free()


func test_unloaded_chunk_stops_safely(t) -> void:
	## Yuklenmemis chunk bosluk sanilmaz: arac dusmez, hasar almadan durur.
	var s := _setup(1)          # yalnizca -16..16 yuklu
	var world: VoxelWorld = s[0]
	var vehicles: Vehicles = s[1]
	var car := vehicles._create("sedan", "sedan", Vector3(0.5, 0.0, 0.5), 0.0)
	car.fuel = 20.0
	var durability: float = car.durability
	vehicles.enter(car)
	_drive(vehicles, 600, 1.0)
	t.ok(car.position.z > -16.0 - 0.05, "yuklenmemis bolgeye girilmemeli (z=%.2f)" % car.position.z)
	t.ok(car.position.y > -0.05, "arac dusmemeli (y=%.2f)" % car.position.y)
	t.eq(car.durability, durability, "guvenli durus hasarsiz")
	t.ok(absf(car.speed) < 0.5, "arac durmali (hiz %.2f)" % car.speed)
	t.ok(world.chunks.size() > 0, "dunya yuklu")
	vehicles.queue_free()


func test_reverse_is_explicit(t) -> void:
	## Ileri giderken S once FREN; durduktan sonra geri vites. W de ayni sekilde.
	var s := _setup()
	var vehicles: Vehicles = s[1]
	var car := vehicles._create("sedan", "sedan", Vector3(0.5, 0.0, 0.5), 0.0)
	car.fuel = 20.0
	vehicles.enter(car)
	_drive(vehicles, 60, 1.0)
	var fwd: float = car.speed
	t.ok(fwd > 2.0, "gaz ileri hizlandirir (%.2f)" % fwd)
	_drive(vehicles, 6, -1.0)
	t.ok(car.speed > 0.0 and car.speed < fwd, "ileri giderken S fren yapar, aniden geri gitmez")
	_drive(vehicles, 240, -1.0)
	t.ok(car.speed < -0.5, "durduktan sonra S geri vites (%.2f)" % car.speed)
	t.eq(vehicles.gear_label(), "G", "vites gostergesi geri")
	_drive(vehicles, 3, 1.0)
	t.ok(car.speed < 0.0, "geri giderken W once frenler")
	vehicles.queue_free()


func test_steering_needs_speed_and_self_centers(t) -> void:
	var s := _setup()
	var vehicles: Vehicles = s[1]
	var car := vehicles._create("sedan", "sedan", Vector3(0.5, 0.0, 0.5), 0.0)
	car.fuel = 20.0
	vehicles.enter(car)
	_drive(vehicles, 30, 0.0, 1.0)
	t.ok(absf(car.yaw) < 0.01, "dururken direksiyon araci dondurmez")
	_drive(vehicles, 60, 1.0, 1.0)
	t.ok(car.yaw < -0.05, "D saga dondurur (yaw %.2f)" % car.yaw)
	_drive(vehicles, 30, 1.0, 0.0)
	t.ok(absf(float(car.steer)) < 0.05, "birakinca direksiyon toparlanir")
	vehicles.queue_free()


func test_no_exit_at_speed(t) -> void:
	var s := _setup()
	var vehicles: Vehicles = s[1]
	var car := vehicles._create("sedan", "sedan", Vector3(0.5, 0.0, 0.5), 0.0)
	car.fuel = 20.0
	vehicles.enter(car)
	car.speed = 9.0
	t.ok(vehicles.can_exit() != "", "hizliyken inilmez")
	car.speed = 0.5
	t.eq(vehicles.can_exit(), "", "dururken inilir")
	vehicles.queue_free()


func test_driver_view_uses_open_shell_and_cabin(t) -> void:
	## Surucu koltugunda eski dolu model gizlenir, acik kabuk + kabin kurulur;
	## goz modele ozel `driver_eye` noktasindan gelir.
	var s := _setup()
	var vehicles: Vehicles = s[1]
	for model: String in ["sedan", "van", "minibus"]:
		var car := vehicles._create(Vehicles.MODEL_TO_DEF[model], model, Vector3(0.5, 0.0, 0.5 + 12.0 * vehicles.entries.size()), 0.0)
		vehicles.enter(car)
		var pair := AssetLibrary.vehicle_pair(model)
		t.ok(not pair.is_empty(), "%s icin acik kabuk/kabin cifti olmali" % model)
		t.ok(not car.node.visible, "%s: dolu model gizli" % model)
		t.ok(car.rig != null and car.cabin != null, "%s: kabin kurulu" % model)
		t.ok(AssetLibrary.has_marker(pair.cabin, "driver_eye"), "%s: driver_eye marker'i" % model)
		var eye := vehicles.driver_eye_local(car)
		t.ok(eye.y > 0.8 and eye.y < float(car.height) + 0.3, "%s: goz yuksekligi makul (%.2f)" % [model, eye.y])
		vehicles.leave()
		t.ok(car.node.visible and car.rig == null, "%s: inince dolu model geri gelir" % model)
	vehicles.queue_free()


func test_exit_point_avoids_wall_and_water(t) -> void:
	var s := _setup()
	var world: VoxelWorld = s[0]
	var vehicles: Vehicles = s[1]
	# Sol tarafi duvar.
	for z in range(-3, 4):
		for y in range(0, 3):
			world.set_block(Vector3i(-2, y, z), _m("brick"), VoxelWorld.ORIGIN_WORLD)
	var car := vehicles._create("sedan", "sedan", Vector3(0.5, 0.0, 0.5), 0.0)
	vehicles.enter(car)
	var point := vehicles.exit_point(0.3, 1.8)
	t.ok(point != Vector3.INF, "bir inis noktasi bulunmali")
	t.ok(point.x > 0.5, "duvar tarafina inilmemeli (x=%.2f)" % point.x)
	t.ok(not VoxelBody.is_blocked(world, point, 0.3, 1.8), "inis noktasi bos olmali")
	vehicles.queue_free()


func test_refuel_uses_real_items(t) -> void:
	var s := _setup()
	var vehicles: Vehicles = s[1]
	var car := vehicles._create("sedan", "sedan", Vector3(0.5, 0.0, 0.5), 0.0)
	car.fuel = 0.0
	var bag := Inventory.new()
	var message := vehicles.refuel(car, bag)
	t.ok(car.fuel == 0.0 and message.contains("yok"), "yakit esyasi yokken dolmamali")
	bag.add(ItemStack.new(Content.item("gasoline"), 3))
	vehicles.refuel(car, bag)
	t.ok(car.fuel > 0.0, "benzinle dolmali")
	t.ok(bag.count("gasoline") < 3, "benzin harcanmali")
	vehicles.queue_free()
