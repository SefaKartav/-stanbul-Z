class_name BlockTextures
extends RefCounted
## Blok dokulari: 16x16 pixel-art, prosedurel uretilir.
##
## YER TUTUCU ILE FINAL ASSET AYNI KIMLIGIN ARKASINDA
##   Her doku bir kimlikle istenir ("brick", "asphalt"...). res://assets/
##   blocks/<kimlik>.png varsa O kullanilir; yoksa burada tohumdan ciziliir.
##   Kullanici final dokulari hazirladiginda dosyayi klasore koyar, kod
##   degismez. Final asset olmadan da oyun eksiksiz acilir.
##
## Dokular bir Texture2DArray'e (katman = doku) toplanir: atlas yerine dizi
## kullanmak mipmap'lerde komsu dokunun tasmasini (bleeding) engeller.

const SIZE := 16
const OVERRIDE_DIR := "res://assets/blocks/"


static func build_array(texture_ids: PackedStringArray) -> Texture2DArray:
	var images: Array[Image] = []
	for texture_id in texture_ids:
		images.append(image_for(texture_id))
	var array := Texture2DArray.new()
	array.create_from_images(images)
	return array


static func image_for(texture_id: String) -> Image:
	var path := OVERRIDE_DIR + texture_id + ".png"
	if ResourceLoader.exists(path):
		var texture: Texture2D = load(path)
		if texture != null:
			var loaded := texture.get_image()
			if loaded != null:
				loaded.decompress()
				loaded.convert(Image.FORMAT_RGBA8)
				if loaded.get_width() != SIZE or loaded.get_height() != SIZE:
					loaded.resize(SIZE, SIZE, Image.INTERPOLATE_NEAREST)
				loaded.generate_mipmaps()
				return loaded
	var image := generate(texture_id)
	soften(image)
	image.generate_mipmaps()
	return image


static func soften(image: Image, amount: float = 0.42) -> void:
	## YUMUSAK DOKU (29 Eylul 2026): her pikseli 3x3 komsu ortalamasina dogru
	## ceker (kenarlar sarmalanir: doku dosenince dikis olusmaz). Desen
	## (tugla derzi, tahta cizgisi) okunur kalir; piksel "kumu" ve sert
	## kontrast azalir. Saydam piksel komsu olarak sayilmaz, saydamlik aynen kalir.
	var src := image.duplicate() as Image
	for y in SIZE:
		for x in SIZE:
			var c := src.get_pixel(x, y)
			if c.a < 0.5:
				continue
			var sum := Vector3.ZERO
			var n := 0
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var o := src.get_pixel((x + dx + SIZE) % SIZE, (y + dy + SIZE) % SIZE)
					if o.a >= 0.5:
						sum += Vector3(o.r, o.g, o.b)
						n += 1
			var avg := sum / float(maxi(1, n))
			image.set_pixel(x, y, Color(lerpf(c.r, avg.x, amount), lerpf(c.g, avg.y, amount), lerpf(c.b, avg.z, amount), c.a))


static func crack_array() -> Texture2DArray:
	## Hasar catlaklari: katman 0 bos, 1-3 giderek yogunlasan catlak.
	var images: Array[Image] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 991
	var cracks := _crack_paths(rng)
	for stage in 4:
		var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
		image.fill(Color(0, 0, 0, 0))
		var count: int = [0, 2, 4, 7][stage]
		for c in count:
			for p: Vector2i in cracks[c]:
				image.set_pixelv(p, Color(0.05, 0.04, 0.04, 0.85))
		image.generate_mipmaps()
		images.append(image)
	var array := Texture2DArray.new()
	array.create_from_images(images)
	return array


static func _crack_paths(rng: RandomNumberGenerator) -> Array:
	var paths: Array = []
	for _c in 7:
		var p := Vector2i(rng.randi_range(3, 12), rng.randi_range(3, 12))
		var path: Array = []
		var dir := Vector2i([-1, 1][rng.randi_range(0, 1)], [-1, 1][rng.randi_range(0, 1)])
		for _s in rng.randi_range(4, 8):
			path.append(p)
			if rng.randf() < 0.5:
				p.x += dir.x
			else:
				p.y += dir.y
			p = p.clamp(Vector2i.ZERO, Vector2i(15, 15))
		paths.append(path)
	return paths


# ---------------------------------------------------------------------------
# Prosedurel cizim
# ---------------------------------------------------------------------------
static func generate(texture_id: String) -> Image:
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(texture_id)
	match texture_id:
		"asphalt": _speckle(image, rng, Color8(62, 64, 68), 0.025, [Color8(78, 78, 80), Color8(52, 53, 56)], 0.18)
		"sidewalk": _tiles(image, rng, Color8(158, 152, 142), Color8(118, 112, 104), 8, 8, 0.05)
		"curb": _curb(image, rng)
		"dirt": _speckle(image, rng, Color8(106, 80, 56), 0.1, [Color8(84, 62, 42), Color8(128, 100, 70)], 0.2)
		"grass_top": _speckle(image, rng, Color8(86, 124, 60), 0.1, [Color8(104, 146, 70), Color8(66, 100, 48)], 0.3)
		"grass_side": _grass_side(image, rng)
		"stone": _stone(image, rng, Color8(122, 120, 114))
		"brick": _bricks(image, rng, Color8(152, 74, 56), Color8(186, 176, 160), 4, 8)
		"concrete": _speckle(image, rng, Color8(150, 150, 146), 0.05, [Color8(132, 132, 128), Color8(166, 166, 160)], 0.1, true)
		"plaster_cream": _plaster(image, rng, Color8(216, 202, 170))
		"plaster_blue": _plaster(image, rng, Color8(98, 134, 152))
		"plaster_rose": _plaster(image, rng, Color8(186, 114, 104))
		"plaster_white": _plaster(image, rng, Color8(222, 220, 212))
		"wood_plank": _planks(image, rng, Color8(152, 110, 68), 4)
		"wood_old": _planks(image, rng, Color8(112, 84, 60), 3, true)
		"glass": _glass(image, rng)
		"steel": _steel(image, rng)
		"roof_tile": _roof_tiles(image, rng)
		"limestone": _bricks(image, rng, Color8(208, 198, 172), Color8(176, 166, 142), 8, 16, 0.04)
		"water": _water(image, rng)
		"sand": _speckle(image, rng, Color8(204, 188, 142), 0.06, [Color8(186, 170, 124), Color8(222, 208, 164)], 0.25)
		"rubble": _rubble(image, rng)
		"metal_sheet": _metal_sheet(image, rng)
		"interior": _interior(image, rng)
		"sandbag": _sandbags(image, rng)
		"cinderblock": _bricks(image, rng, Color8(142, 142, 138), Color8(104, 104, 100), 8, 16, 0.05)
		"window_frame": _window_frame(image, rng)
		"cobblestone": _cobbles(image, rng)
		"leaves": _leaves(image, rng)
		"log_top": _log_top(image, rng)
		"log_side": _log_side(image, rng)
		"roof_flat": _speckle(image, rng, Color8(76, 76, 80), 0.06, [Color8(62, 62, 66), Color8(96, 94, 92)], 0.15)
		"railing": _railing(image, rng)
		"barricade": _barricade(image, rng)
		"bridge_steel": _bridge_steel(image, rng)
		"asphalt_line": _asphalt_line(image, rng)
		"interior_plaster": _plaster(image, rng, Color8(222, 214, 196))
		"interior_parquet": _parquet(image, rng)
		"interior_tile": _tiles(image, rng, Color8(214, 212, 204), Color8(170, 168, 160), 8, 8, 0.03)
		"stair_tread": _stair_tread(image, rng)
		"ladder": _ladder(image, rng)
		# Oyuncu yapi parcalari (insa kipi): "elle yapilmis" okunmali.
		"pb_frame": _frame(image, rng)
		"pb_wood_reinforced": _wood_reinforced(image, rng)
		"pb_scrap": _scrap(image, rng)
		"pb_stone_block": _bricks(image, rng, Color8(176, 168, 150), Color8(132, 126, 114), 8, 16, 0.05)
		"pb_rconcrete": _rconcrete(image, rng)
		"pb_steel_plate": _steel_plate(image, rng)
		"pb_glass_reinforced": _glass_reinforced(image, rng)
		"pb_bars": _bars(image, rng, 3)
		"pb_mesh": _mesh(image, rng)
		"pb_gabion": _gabion(image, rng)
		"pb_door_wood": _door(image, rng, Color8(132, 94, 60), false)
		"pb_door_reinforced": _door(image, rng, Color8(118, 84, 54), true)
		"pb_door_metal": _door_metal(image, rng, Color8(110, 118, 116))
		"pb_door_steel": _door_metal(image, rng, Color8(86, 92, 98))
		"pb_shingle": _shingle(image, rng)
		"pb_ladder_wood": _ladder_wood(image, rng)
		_:_speckle(image, rng, Color8(200, 0, 200), 0.1, [Color8(40, 0, 40)], 0.5)
	return image


static func _jitter(color: Color, rng: RandomNumberGenerator, amount: float) -> Color:
	var d := rng.randf_range(-amount, amount)
	return Color(clampf(color.r + d, 0, 1), clampf(color.g + d, 0, 1), clampf(color.b + d, 0, 1), color.a)


static func _speckle(image: Image, rng: RandomNumberGenerator, base: Color, noise: float,
		accents: Array, accent_chance: float, cracks: bool = false) -> void:
	for y in SIZE:
		for x in SIZE:
			var c := _jitter(base, rng, noise)
			if rng.randf() < accent_chance:
				c = _jitter(accents[rng.randi() % accents.size()], rng, noise * 0.5)
			image.set_pixel(x, y, c)
	if cracks:
		var p := Vector2i(rng.randi_range(2, 13), rng.randi_range(2, 13))
		for _i in 5:
			image.set_pixelv(p, base.darkened(0.25))
			p += Vector2i(rng.randi_range(-1, 1), 1)
			p = p.clamp(Vector2i.ZERO, Vector2i(15, 15))


static func _tiles(image: Image, rng: RandomNumberGenerator, base: Color, grout: Color,
		w: int, h: int, noise: float) -> void:
	for y in SIZE:
		for x in SIZE:
			var c := _jitter(base, rng, noise)
			if x % w == 0 or y % h == 0:
				c = _jitter(grout, rng, noise * 0.5)
			elif x % w == 1 or y % h == 1:
				c = c.lightened(0.06)
			image.set_pixel(x, y, c)


static func _curb(image: Image, rng: RandomNumberGenerator) -> void:
	for y in SIZE:
		for x in SIZE:
			var c := _jitter(Color8(172, 168, 158), rng, 0.04)
			# Istanbul kaldirim bordurunun kirmizi-beyaz ya da siyah-beyaz seridi
			if y >= 8:
				c = _jitter(Color8(140, 136, 128), rng, 0.04)
			if y == 8:
				c = c.darkened(0.2)
			if x % 8 == 0:
				c = c.darkened(0.15)
			image.set_pixel(x, y, c)


static func _grass_side(image: Image, rng: RandomNumberGenerator) -> void:
	_speckle(image, rng, Color8(106, 80, 56), 0.1, [Color8(84, 62, 42), Color8(128, 100, 70)], 0.2)
	for x in SIZE:
		var depth := rng.randi_range(2, 5)
		for y in depth:
			image.set_pixel(x, y, _jitter(Color8(86, 124, 60), rng, 0.08))


static func _stone(image: Image, rng: RandomNumberGenerator, base: Color) -> void:
	_speckle(image, rng, base, 0.06, [base.darkened(0.15), base.lightened(0.1)], 0.2)
	for _i in 5:
		var p := Vector2i(rng.randi_range(0, 15), rng.randi_range(0, 15))
		for _s in rng.randi_range(2, 5):
			image.set_pixelv(p, base.darkened(0.3))
			p += Vector2i(rng.randi_range(0, 1), rng.randi_range(-1, 1))
			p = p.clamp(Vector2i.ZERO, Vector2i(15, 15))


static func _bricks(image: Image, rng: RandomNumberGenerator, brick: Color, mortar: Color,
		course_h: int, brick_w: int, noise: float = 0.07) -> void:
	for y in SIZE:
		var course := y / course_h
		var offset := (brick_w / 2) if course % 2 == 1 else 0
		for x in SIZE:
			var bx := (x + offset) % brick_w
			var c: Color
			if y % course_h == course_h - 1 or bx == brick_w - 1:
				c = _jitter(mortar, rng, 0.04)
			else:
				# Her tuglanin kendi tonu: duz renk duvar yerine elle orulmus his.
				var brick_id := course * 7 + (x + offset) / brick_w
				var tone := sin(brick_id * 12.9898) * 0.05
				c = _jitter(Color(brick.r + tone, brick.g + tone * 0.6, brick.b + tone * 0.4), rng, noise * 0.6)
				if y % course_h == 0:
					c = c.lightened(0.07)
			image.set_pixel(x, y, c)


static func _plaster(image: Image, rng: RandomNumberGenerator, base: Color) -> void:
	_speckle(image, rng, base, 0.035, [base.darkened(0.08), base.lightened(0.05)], 0.25)
	# Kiyamet sonrasi is/yagmur izi. (Dokulmus siva lekesi kaldirildi: doku
	# her blokta tekrarlandigi icin cephede puantiye desenine donusuyordu.)
	for x in SIZE:
		if rng.randf() < 0.45:
			var length := rng.randi_range(1, 4)
			for y in range(SIZE - length, SIZE):
				image.set_pixel(x, y, image.get_pixel(x, y).darkened(0.12))


static func _planks(image: Image, rng: RandomNumberGenerator, base: Color, plank_h: int, weathered: bool = false) -> void:
	for y in SIZE:
		var plank := y / plank_h
		var tone := sin(plank * 3.7) * 0.06
		for x in SIZE:
			var c := _jitter(Color(base.r + tone, base.g + tone, base.b + tone * 0.5), rng, 0.035)
			if y % plank_h == plank_h - 1:
				c = base.darkened(0.35)
			elif (x + plank * 5) % 11 == 0 and rng.randf() < 0.6:
				c = c.darkened(0.15)
			if weathered and rng.randf() < 0.08:
				c = c.lerp(Color8(120, 120, 110), 0.5)
			image.set_pixel(x, y, c)
		if y % plank_h == 1:
			image.set_pixel((plank * 5 + 2) % SIZE, y, Color8(60, 58, 56))
			image.set_pixel((plank * 5 + 12) % SIZE, y, Color8(60, 58, 56))


static func _glass(image: Image, rng: RandomNumberGenerator) -> void:
	for y in SIZE:
		for x in SIZE:
			var c := Color(0.62, 0.78, 0.86, 0.32)
			if x == 0 or y == 0 or x == 15 or y == 15:
				c = Color(0.82, 0.86, 0.88, 0.9)
			elif (x + y) % 11 == 0 or (x + y) % 11 == 1:
				c = Color(0.86, 0.92, 0.96, 0.4)
			if rng.randf() < 0.03:
				c.a = minf(1.0, c.a + 0.2)
			image.set_pixel(x, y, c)


static func _steel(image: Image, rng: RandomNumberGenerator) -> void:
	for y in SIZE:
		for x in SIZE:
			var c := _jitter(Color8(108, 116, 124), rng, 0.03)
			if x == 0 or y == 0:
				c = c.lightened(0.15)
			if x == 15 or y == 15:
				c = c.darkened(0.25)
			if (x == 2 or x == 13) and (y == 2 or y == 13):
				c = Color8(70, 74, 80)
			if rng.randf() < 0.05:
				c = c.lerp(Color8(130, 84, 52), 0.5)   # pas
			image.set_pixel(x, y, c)


static func _roof_tiles(image: Image, rng: RandomNumberGenerator) -> void:
	for y in SIZE:
		for x in SIZE:
			var row := y / 4
			var ox := 2 if row % 2 == 1 else 0
			var local := (x + ox) % 4
			var c := _jitter(Color8(166, 84, 60), rng, 0.05)
			if y % 4 == 3:
				c = Color8(110, 52, 40)
			elif local == 0:
				c = c.lightened(0.12)
			elif local == 3:
				c = c.darkened(0.12)
			image.set_pixel(x, y, c)


static func _water(image: Image, rng: RandomNumberGenerator) -> void:
	for y in SIZE:
		for x in SIZE:
			var wave := sin((x + y * 0.5) * 0.9) * 0.04
			var c := Color(0.16 + wave, 0.36 + wave, 0.48 + wave, 0.72)
			if rng.randf() < 0.05:
				c = Color(0.5, 0.66, 0.74, 0.8)
			image.set_pixel(x, y, c)


static func _rubble(image: Image, rng: RandomNumberGenerator) -> void:
	_speckle(image, rng, Color8(122, 116, 108), 0.08, [Color8(152, 80, 62), Color8(160, 158, 150), Color8(80, 76, 72)], 0.35)


static func _metal_sheet(image: Image, rng: RandomNumberGenerator) -> void:
	for y in SIZE:
		for x in SIZE:
			var c := _jitter(Color8(116, 122, 124), rng, 0.02)
			if y % 3 == 0:
				c = c.darkened(0.2)
			elif y % 3 == 1:
				c = c.lightened(0.08)
			if rng.randf() < 0.04:
				c = c.lerp(Color8(140, 90, 56), 0.6)
			image.set_pixel(x, y, c)


static func _interior(image: Image, rng: RandomNumberGenerator) -> void:
	# Bina ici: siva + kiris + doseme izi. Tasarlanmis oda DEGIL; cephe
	# kirildiginda arkadaki "dolu hacim" gorunur (belgenin 6. bolumu).
	_speckle(image, rng, Color8(172, 162, 146), 0.04, [Color8(150, 140, 126)], 0.2)
	for x in SIZE:
		image.set_pixel(x, 0, Color8(120, 110, 98))
		image.set_pixel(x, 1, Color8(138, 128, 114))
	for y in range(2, SIZE):
		if rng.randf() < 0.4:
			image.set_pixel(7, y, Color8(150, 140, 126))


static func _sandbags(image: Image, rng: RandomNumberGenerator) -> void:
	for y in SIZE:
		var row := y / 5
		var ox := 4 if row % 2 == 1 else 0
		for x in SIZE:
			var local_y := y % 5
			var local_x := (x + ox) % 8
			var c := _jitter(Color8(170, 152, 110), rng, 0.04)
			if local_y == 4 or local_x == 7:
				c = Color8(96, 86, 62)
			elif local_y == 0:
				c = c.lightened(0.1)
			image.set_pixel(x, y, c)


static func _window_frame(image: Image, rng: RandomNumberGenerator) -> void:
	for y in SIZE:
		for x in SIZE:
			var c := _jitter(Color8(228, 224, 212), rng, 0.03)
			if x == 7 or x == 8 or y == 7 or y == 8:
				c = Color8(200, 196, 184)
			image.set_pixel(x, y, c)


static func _cobbles(image: Image, rng: RandomNumberGenerator) -> void:
	for y in SIZE:
		for x in SIZE:
			var cell_x := (x + (2 if (y / 4) % 2 == 1 else 0)) / 4
			var tone := sin((cell_x * 17 + y / 4 * 31) * 1.3) * 0.06
			var c := _jitter(Color(0.44 + tone, 0.42 + tone, 0.39 + tone), rng, 0.03)
			if y % 4 == 3 or (x + (2 if (y / 4) % 2 == 1 else 0)) % 4 == 3:
				c = Color8(62, 60, 56)
			image.set_pixel(x, y, c)


static func _leaves(image: Image, rng: RandomNumberGenerator) -> void:
	for y in SIZE:
		for x in SIZE:
			var c := _jitter(Color8(70, 106, 56), rng, 0.08)
			if rng.randf() < 0.2:
				c = Color8(52, 80, 42)
			if rng.randf() < 0.1:
				c = Color8(96, 136, 70)
			image.set_pixel(x, y, c)


static func _log_top(image: Image, rng: RandomNumberGenerator) -> void:
	for y in SIZE:
		for x in SIZE:
			var d := Vector2(x - 7.5, y - 7.5).length()
			var c := _jitter(Color8(160, 124, 82), rng, 0.03)
			if int(d) % 3 == 0:
				c = c.darkened(0.15)
			if d > 6.5:
				c = Color8(92, 70, 48)
			image.set_pixel(x, y, c)


static func _log_side(image: Image, rng: RandomNumberGenerator) -> void:
	for y in SIZE:
		for x in SIZE:
			var c := _jitter(Color8(96, 72, 50), rng, 0.05)
			if x % 4 == 0:
				c = c.darkened(0.2)
			image.set_pixel(x, y, c)


static func _barricade(image: Image, rng: RandomNumberGenerator) -> void:
	# Capraz cakilmis tahtalar + civi basliklari: "oyuncu yapti" diye okunmali.
	_planks(image, rng, Color8(128, 92, 58), 5, true)
	for i in SIZE:
		for w in 2:
			var x := clampi(i + w, 0, 15)
			image.set_pixel(x, i, Color8(96, 66, 40))
			image.set_pixel(15 - x, i, Color8(104, 72, 44))
	for p: Vector2i in [Vector2i(2, 2), Vector2i(13, 2), Vector2i(2, 13), Vector2i(13, 13), Vector2i(7, 7)]:
		image.set_pixelv(p, Color8(70, 70, 72))


static func _bridge_steel(image: Image, rng: RandomNumberGenerator) -> void:
	# Boyali kopru celigi: acik gri paneller, perçin sirasi, ince pas izi.
	for y in SIZE:
		for x in SIZE:
			var c := _jitter(Color8(192, 194, 192), rng, 0.02)
			if y % 8 == 0:
				c = c.darkened(0.22)
			elif y % 8 == 1:
				c = c.lightened(0.06)
			if x == 0:
				c = c.darkened(0.15)
			if (y % 8 == 3) and x % 4 == 2:
				c = Color8(150, 152, 150)
			if y % 8 == 7 and rng.randf() < 0.15:
				c = c.lerp(Color8(140, 96, 70), 0.4)
			image.set_pixel(x, y, c)


static func _parquet(image: Image, rng: RandomNumberGenerator) -> void:
	# Balikkilcigi degil, duz serit parke: 4 piksellik tahtalar, kaydirmali ek.
	for y in SIZE:
		var strip := y / 4
		var joint := (strip * 5) % 16
		for x in SIZE:
			var tone := sin((strip * 7 + (1 if x > joint else 0)) * 2.1) * 0.05
			var c := _jitter(Color(0.58 + tone, 0.42 + tone, 0.27 + tone * 0.5), rng, 0.025)
			if y % 4 == 3 or x == joint:
				c = c.darkened(0.3)
			image.set_pixel(x, y, c)


static func _stair_tread(image: Image, rng: RandomNumberGenerator) -> void:
	# Mozaik basamak: acik gri tas, on kenarda kaymaz koyu serit.
	_speckle(image, rng, Color8(186, 180, 170), 0.04, [Color8(160, 154, 146), Color8(206, 200, 190)], 0.25)
	for x in SIZE:
		image.set_pixel(x, 0, Color8(92, 88, 84))
		image.set_pixel(x, 1, Color8(112, 108, 102))


static func _asphalt_line(image: Image, rng: RandomNumberGenerator) -> void:
	# Asfalt ustunde yipranmis beyaz boya. Serit yonu blok izgarasina gore
	# capraz olabildigi icin boya karenin ortasinda yuvarlak bir leke olarak
	# durur; ardisik bloklar kesik bir cizgi gibi okunur.
	_speckle(image, rng, Color8(62, 64, 68), 0.025, [Color8(78, 78, 80), Color8(52, 53, 56)], 0.18)
	for y in SIZE:
		for x in SIZE:
			if Vector2(x - 7.5, y - 7.5).length() < 5.5 and rng.randf() < 0.86:
				image.set_pixel(x, y, _jitter(Color8(214, 212, 200), rng, 0.04))


static func _ladder(image: Image, rng: RandomNumberGenerator) -> void:
	## Tirmanma merdiveni: iki celik dikme + basamaklar, arasi saydam.
	for y in SIZE:
		for x in SIZE:
			var c := Color(0, 0, 0, 0)
			if x <= 1 or x >= 14 or y % 4 == 1:
				c = _jitter(Color8(92, 96, 98), rng, 0.05)
			image.set_pixel(x, y, c)


static func _railing(image: Image, rng: RandomNumberGenerator) -> void:
	for y in SIZE:
		for x in SIZE:
			var c := Color(0, 0, 0, 0)
			if y <= 1 or x % 4 == 1:
				c = _jitter(Color8(64, 68, 70), rng, 0.04)
			image.set_pixel(x, y, c)


# ---------------------------------------------------------------------------
# Oyuncu yapi parcalari
# ---------------------------------------------------------------------------
static func _frame(image: Image, rng: RandomNumberGenerator) -> void:
	## Iskelet: kenar kalaslari + capraz destek, arasi saydam (taslak asamasi).
	for y in SIZE:
		for x in SIZE:
			var c := Color(0, 0, 0, 0)
			if x <= 1 or x >= 14 or y <= 1 or y >= 14 or absi(x - y) <= 0:
				c = _jitter(Color8(166, 126, 80), rng, 0.05)
				if x == 0 or y == 0:
					c = c.lightened(0.08)
			image.set_pixel(x, y, c)


static func _wood_reinforced(image: Image, rng: RandomNumberGenerator) -> void:
	_planks(image, rng, Color8(138, 100, 64), 4)
	# Yatay iki celik lama + civata basliklari.
	for y: int in [3, 12]:
		for x in SIZE:
			image.set_pixel(x, y, _jitter(Color8(84, 88, 92), rng, 0.03))
		for x: int in [2, 8, 13]:
			image.set_pixel(x, y, Color8(150, 152, 150))


static func _scrap(image: Image, rng: RandomNumberGenerator) -> void:
	## Hurda sac yamasi: farkli tonlarda levhalar, perçin ve pas.
	var tones := [Color8(118, 120, 116), Color8(104, 112, 118), Color8(128, 114, 96), Color8(96, 104, 98)]
	for y in SIZE:
		for x in SIZE:
			var patch := (x / 8) + (y / 6) * 2
			var c := _jitter(tones[patch % tones.size()], rng, 0.03)
			if x % 8 == 0 or y % 6 == 0:
				c = c.darkened(0.3)
			elif (x % 8 == 1 or x % 8 == 6) and y % 6 == 2:
				c = Color8(166, 166, 160)
			if rng.randf() < 0.07:
				c = c.lerp(Color8(138, 82, 48), 0.55)
			image.set_pixel(x, y, c)


static func _rconcrete(image: Image, rng: RandomNumberGenerator) -> void:
	## Betonarme: kalip izli beton + gorunen donati ucu.
	_speckle(image, rng, Color8(140, 140, 138), 0.04, [Color8(122, 122, 120), Color8(156, 156, 152)], 0.12)
	for x in SIZE:
		image.set_pixel(x, 7, image.get_pixel(x, 7).darkened(0.12))
	for p: Vector2i in [Vector2i(3, 3), Vector2i(12, 3), Vector2i(3, 11), Vector2i(12, 11)]:
		image.set_pixelv(p, Color8(96, 88, 82))


static func _steel_plate(image: Image, rng: RandomNumberGenerator) -> void:
	## Cift panel celik: kaynak dikisi ve perçin sirasi.
	for y in SIZE:
		for x in SIZE:
			var c := _jitter(Color8(92, 98, 104), rng, 0.025)
			if y == 7 or y == 8:
				c = Color8(70, 74, 78) if y == 7 else Color8(116, 120, 124)
			if (y == 2 or y == 13) and x % 3 == 1:
				c = Color8(140, 144, 146)
			if x == 0 or x == 15:
				c = c.darkened(0.2)
			image.set_pixel(x, y, c)


static func _glass_reinforced(image: Image, rng: RandomNumberGenerator) -> void:
	_glass(image, rng)
	# Tel izgarali cam: seyrek koyu tel.
	for y in SIZE:
		for x in SIZE:
			if x % 5 == 2 or y % 5 == 2:
				image.set_pixel(x, y, Color(0.36, 0.4, 0.42, 0.75))


static func _bars(image: Image, rng: RandomNumberGenerator, every: int) -> void:
	for y in SIZE:
		for x in SIZE:
			var c := Color(0, 0, 0, 0)
			if x % every == 1 or y <= 1 or y >= 14:
				c = _jitter(Color8(58, 60, 62), rng, 0.04)
				if x % every == 1 and rng.randf() < 0.08:
					c = c.lerp(Color8(120, 70, 40), 0.5)
			image.set_pixel(x, y, c)


static func _mesh(image: Image, rng: RandomNumberGenerator) -> void:
	for y in SIZE:
		for x in SIZE:
			var c := Color(0, 0, 0, 0)
			if (x + y) % 4 == 0 or (x - y + 16) % 4 == 0:
				c = _jitter(Color8(150, 154, 152), rng, 0.05)
			if x == 0 or x == 15:
				c = Color8(80, 84, 86)
			image.set_pixel(x, y, c)


static func _gabion(image: Image, rng: RandomNumberGenerator) -> void:
	## Tel kafes icinde tas: gri taslar + parlak tel izgarasi.
	_stone(image, rng, Color8(128, 124, 116))
	for y in SIZE:
		for x in SIZE:
			if x % 5 == 0 or y % 5 == 0:
				image.set_pixel(x, y, _jitter(Color8(170, 172, 168), rng, 0.04))


static func _door(image: Image, rng: RandomNumberGenerator, base: Color, reinforced: bool) -> void:
	## Dikey tahtali kapi: cerceve, tokmak; takviyeli olanda Z lama.
	for y in SIZE:
		for x in SIZE:
			var board := x / 4
			var c := _jitter(Color(base.r + sin(board * 2.3) * 0.04, base.g, base.b), rng, 0.03)
			if x % 4 == 3:
				c = base.darkened(0.3)
			if x == 0 or x == 15 or y == 0 or y == 15:
				c = base.darkened(0.4)
			image.set_pixel(x, y, c)
	if reinforced:
		for i in range(2, 14):
			image.set_pixel(i, 3, Color8(80, 82, 84))
			image.set_pixel(i, 12, Color8(80, 82, 84))
			image.set_pixel(i, 15 - i, Color8(88, 90, 92))
	image.set_pixel(12, 8, Color8(196, 170, 96))
	image.set_pixel(12, 9, Color8(150, 128, 70))


static func _door_metal(image: Image, rng: RandomNumberGenerator, base: Color) -> void:
	for y in SIZE:
		for x in SIZE:
			var c := _jitter(base, rng, 0.02)
			if x == 0 or x == 15 or y == 0 or y == 15:
				c = base.darkened(0.35)
			elif (x == 3 or x == 12) and y > 2 and y < 13:
				c = base.darkened(0.15)
			elif (y == 3 or y == 12) and x > 2 and x < 13:
				c = base.lightened(0.1)
			if rng.randf() < 0.03:
				c = c.lerp(Color8(130, 84, 52), 0.4)
			image.set_pixel(x, y, c)
	image.set_pixel(13, 8, Color8(40, 40, 42))
	image.set_pixel(13, 9, Color8(200, 200, 196))


static func _shingle(image: Image, rng: RandomNumberGenerator) -> void:
	## Ahsap pul kiremit: kaydirmali kisa tahtalar, alt kenar golgesi.
	for y in SIZE:
		var row := y / 4
		var ox := 3 if row % 2 == 1 else 0
		for x in SIZE:
			var piece := (x + ox) / 5
			var tone := sin((row * 9 + piece) * 1.7) * 0.05
			var c := _jitter(Color(0.47 + tone, 0.34 + tone, 0.22 + tone * 0.5), rng, 0.03)
			if y % 4 == 3:
				c = c.darkened(0.35)
			elif (x + ox) % 5 == 0:
				c = c.darkened(0.2)
			image.set_pixel(x, y, c)


static func _ladder_wood(image: Image, rng: RandomNumberGenerator) -> void:
	for y in SIZE:
		for x in SIZE:
			var c := Color(0, 0, 0, 0)
			if x <= 1 or x >= 14 or y % 4 == 1:
				c = _jitter(Color8(146, 104, 64), rng, 0.05)
			image.set_pixel(x, y, c)
