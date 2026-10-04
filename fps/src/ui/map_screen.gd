class_name MapScreen
extends Screen
## Sehir haritasi (M): fareyle yakinlastir/kaydir, oyuncuya don, hedef
## isareti, katmanlar (usler, tehlike, kaynaklar, kopru).
##
## Oynanista zoom kademesi YOKTUR (FPS); harita bunun yerini alir. Harita
## goruntusu harita verisinden BIR KEZ cizilir ve onbellege alinir.
## Bu ekran dunyayi DURDURUR.

var view: Control
var texture: ImageTexture
var zoom := 2.0
var pan := Vector2.ZERO
var layers := {"bases": true, "danger": true, "resources": true, "bridge": true, "places": true}
## Kurum isaretleri: tur -> [renk, kisaltma, ad]. Harita Seti (map_tool)
## cantadaysa hepsi; yoksa yalnizca 350 m icindekiler gorunur.
const POI_STYLE := {
	"military": [Color(0.55, 0.7, 0.4), "A", "Askerî alan"], "checkpoint": [Color(0.95, 0.5, 0.3), "K", "Kontrol noktası"],
	"hospital": [Color(0.95, 0.35, 0.35), "H", "Hastane"], "clinic": [Color(0.95, 0.6, 0.6), "S", "Sağlık ocağı"],
	"pharmacy": [Color(0.4, 0.85, 0.5), "E", "Eczane"], "school": [Color(0.95, 0.8, 0.3), "O", "Okul"],
	"prison": [Color(0.7, 0.55, 0.75), "C", "Hapishane"], "historic": [Color(0.95, 0.9, 0.75), "T", "Tarihî odak"],
	"ferry_terminal": [Color(0.55, 0.8, 1.0), "~", "İskele"], "bridge": [Color(0.75, 0.85, 1.0), "=", "Geçit"],
}
const NEAR_POI_M := 350.0
var _dragging := false
static var _cached: ImageTexture
static var _cached_id := ""
static var _cached_res := 1.0          # goruntu pikseli basina oyun metresi


func _init() -> void:
	super._init()
	title = "Harita"
	toggle_action = "map"
	pauses_world = true


func _build_content() -> void:
	var side := Screen.column(300, false)
	body.add_child(side)
	for key: String in layers:
		var box := CheckBox.new()
		box.text = {"bases": "Üsler", "danger": "Tehlike (zombi)", "resources": "Kaynaklar (aranmamış binalar)",
			"bridge": "Köprü / geçitler", "places": "Kurumlar ve semtler"}[key]
		box.button_pressed = layers[key]
		box.toggled.connect(func(on: bool) -> void:
			layers[key] = on
			view.queue_redraw())
		side.add_child(box)
	side.add_child(UiTheme.button("Oyuncuya don", _center))
	side.add_child(UiTheme.button("Hedefi kaldir", func() -> void:
		game.waypoint = Vector3.INF
		view.queue_redraw()))
	side.add_child(UiTheme.label("Tekerlek: yakinlastir\nSurukle: kaydir\nSol tik: hedef isareti koy", 18, UiTheme.MUTED))
	var city_l: CityGenerator = game.generator if game.generator is CityGenerator else null
	var fictional := city_l != null and bool(city_l.data.get("fictional", false))
	side.add_child(UiTheme.section("Lejant"))
	for kind: String in POI_STYLE:
		var style: Array = POI_STYLE[kind]
		side.add_child(UiTheme.label("%s  %s" % [style[1], style[2]], 15, style[0]))
	side.add_child(UiTheme.label("Tüm kurumlar için çantada Harita Seti taşı; yoksa yalnızca %d m çevresi." % int(NEAR_POI_M)
		if not _has_map_kit() else "Harita Seti: tüm kurumlar işaretli.", 14, UiTheme.MUTED))
	var license := UiTheme.label("Özgün kurgusal şehir (Istanbul-Z)." if fictional
		else "Harita verisi (c) OpenStreetMap katkıcıları, ODbL.", 14, UiTheme.MUTED)
	side.add_child(license)
	view = Control.new()
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view.clip_contents = true
	view.mouse_filter = Control.MOUSE_FILTER_STOP
	view.gui_input.connect(_on_view_input)
	view.draw.connect(_draw_map)
	body.add_child(view)
	texture = _texture()
	footer.text = "Kuzey yukarida. Kirmizi noktalar: son bilinen zombi yogunlugu. Sari: aranmamis dukkanlar."
	# Ilk yerlesimde gorunum yanlis boyutla olculur; oyuncu elle kaydirana
	# kadar her boyut degisiminde yeniden ortala.
	view.resized.connect(func() -> void:
		if not _user_moved:
			_center())


var _user_moved := false
var _resource_ids := PackedInt32Array()


func _texture() -> ImageTexture:
	var city: CityGenerator = game.generator if game.generator is CityGenerator else null
	if city == null:
		return null
	if _cached != null and _cached_id == city.map_id:
		return _cached
	var prepared: Dictionary = city.data.get("map_image", {})
	if not prepared.is_empty():
		# Buyuk (v2) harita: goruntu harita araci tarafindan HAZIR cizilir.
		# 8 x 10 km'yi sutun sutun burada cizmek dakikalar surerdi.
		var png := Image.new()
		if png.load_png_from_buffer(Marshalls.base64_to_raw(str(prepared.get("png", "")))) == OK:
			_cached = ImageTexture.create_from_image(png)
			_cached_id = city.map_id
			_cached_res = float(prepared.get("res", 1))
			return _cached
	_cached_res = 1.0
	var image := Image.create(city.width, city.height, false, Image.FORMAT_RGB8)
	for z in city.height:
		for x in city.width:
			var info := city.column_info(x, z)
			var c := Color(0.32, 0.31, 0.29)
			match info.kind:
				"sea": c = Color(0.14, 0.26, 0.36)
				"road": c = Color(0.2, 0.2, 0.22) if info.surface == city.m.asphalt else Color(0.42, 0.4, 0.37)
				"sidewalk": c = Color(0.55, 0.53, 0.5)
				"park": c = Color(0.26, 0.42, 0.22)
				"cemetery": c = Color(0.3, 0.38, 0.28)
				"pier": c = Color(0.48, 0.36, 0.24)
				"plaza": c = Color(0.46, 0.44, 0.41)
				"building":
					var b: Dictionary = city.buildings[info.building]
					var cls := Content.building_class(b.class)
					c = cls.color.lightened(0.15) if info.get("edge", false) else cls.color
			var shade: float = 1.0 + (int(info.surface_half) - 6) * 0.01
			image.set_pixel(x, z, c * shade)
	_cached = ImageTexture.create_from_image(image)
	_cached_id = city.map_id
	return _cached


func _center() -> void:
	var p: Vector3 = game.player.global_position
	pan = view.size * 0.5 - Vector2(p.x, p.z) * zoom
	view.queue_redraw()


func _to_screen(world: Vector3) -> Vector2:
	return Vector2(world.x, world.z) * zoom + pan


func _on_view_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_WHEEL_UP or mouse.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var factor := 1.2 if mouse.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.2
			var before := (mouse.position - pan) / zoom
			zoom = clampf(zoom * factor, 0.06, 12.0)
			pan = mouse.position - before * zoom
			_user_moved = true
			view.queue_redraw()
		elif mouse.button_index == MOUSE_BUTTON_RIGHT or mouse.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = mouse.pressed
		elif mouse.button_index == MOUSE_BUTTON_LEFT and mouse.pressed:
			if mouse.double_click:
				return
			var p := (mouse.position - pan) / zoom
			game.waypoint = Vector3(p.x, 0.0, p.y)
			view.queue_redraw()
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _dragging or (motion.button_mask & MOUSE_BUTTON_MASK_LEFT and Input.is_key_pressed(KEY_SHIFT)):
			pan += motion.relative
			_user_moved = true
			view.queue_redraw()


func _draw_map() -> void:
	view.draw_rect(Rect2(Vector2.ZERO, view.size), Color(0.08, 0.09, 0.1))
	if texture != null:
		view.draw_texture_rect(texture, Rect2(pan, texture.get_size() * _cached_res * zoom), false)
	var font := ThemeDB.fallback_font
	if layers.resources and game.registry != null:
		var city: CityGenerator = game.generator
		if _resource_ids.is_empty():
			# Koridor haritasinda 27 bin bina var; her surukleme karesinde hepsini
			# gezmek yerine konut disi binalarin listesi bir kez cikarilir.
			for index in city.buildings.size():
				if not city.buildings[index].class in ["residential", "derelict"]:
					_resource_ids.append(index)
		var visible := Rect2(-pan / zoom, view.size / zoom).grow(10.0)
		for index in _resource_ids:
			var b: Dictionary = city.buildings[index]
			if not visible.has_point(b.centroid) or game.registry.is_touched(index):
				continue
			var c: Vector2 = b.centroid * zoom + pan
			view.draw_circle(c, maxf(2.0, zoom * 1.2), Color(0.95, 0.8, 0.3, 0.85))
	var skills: SkillProfile = game.skills
	if layers.danger:
		# Duyulan (40 m) zombiler; "Rota raporlari" becerisiyle 150 m.
		var reach := 150.0 if skills.has_behavior("danger_map") else 40.0
		for zombie: Zombie in game.zombies.zombies:
			if is_instance_valid(zombie) and zombie.global_position.distance_to(game.player.global_position) < reach:
				view.draw_circle(_to_screen(zombie.global_position), maxf(2.0, zoom * 0.8), Color(0.9, 0.2, 0.15, 0.8))
	if layers.resources and game.props != null:
		# Su noktalari: 400 m icindekiler; "Kesif isaretleri" becerisiyle hepsi.
		var all_water := skills.has_behavior("map_marks")
		for e: Dictionary in game.props.entries:
			if e.kind != "water_source" or e.get("removed", false):
				continue
			if not all_water and Vector2(e.pos.x, e.pos.z).distance_to(Vector2(game.player.global_position.x, game.player.global_position.z)) > 400.0:
				continue
			view.draw_circle(_to_screen(e.pos), maxf(3.0, zoom * 1.4), Color(0.35, 0.7, 1.0, 0.9))
		if skills.has_behavior("map_marks") and game.registry != null:
			var city_m: CityGenerator = game.generator
			var vis := Rect2(-pan / zoom, view.size / zoom).grow(10.0)
			for index in _resource_ids:
				var b: Dictionary = city_m.buildings[index]
				if vis.has_point(b.centroid) and game.registry.is_touched(index):
					view.draw_circle(b.centroid * zoom + pan, maxf(2.0, zoom * 1.0), Color(0.5, 0.5, 0.5, 0.8))
	if skills.has_behavior("radio_all") or game.quests.flags.has("network"):
		for w: Dictionary in game.survivors.waiting_points():
			var c := _to_screen(w.position)
			view.draw_circle(c, 6.0, Color(0.95, 0.95, 0.5))
			view.draw_string(font, c + Vector2(9, 5), str(w.name), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.95, 0.95, 0.6))
	# Gorev hedefleri (ana: altin, yan: acik mavi).
	for q: Dictionary in game.quests.active():
		var qp: Vector3 = game.quests.objective_position(q)
		if qp == Vector3.INF:
			continue
		var c := _to_screen(qp)
		var main := QuestSystem.is_main(q.id)
		var col := UiTheme.ACCENT if main else Color(0.6, 0.85, 1.0)
		view.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -9), c + Vector2(9, 0), c + Vector2(0, 9), c + Vector2(-9, 0)]), col)
		view.draw_string(font, c + Vector2(12, 6), str(q.title), HORIZONTAL_ALIGNMENT_LEFT, -1, 17 if main else 15, col)
	if layers.bases:
		for base: Settlement in game.bases.settlements:
			var c := _to_screen(base.centre())
			view.draw_circle(c, 9.0, Color(0.3, 0.8, 0.4) if not base.breached else Color(0.9, 0.4, 0.2))
			view.draw_string(font, c + Vector2(12, 6), base.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
		for entry: Dictionary in game.pickups.entries:
			if entry.kind == "pack":
				view.draw_string(font, _to_screen(entry.position) - Vector2(6, -6), "X", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 0.3, 0.3))
	if layers.bridge and game.generator is CityGenerator:
		for deck: Dictionary in (game.generator as CityGenerator).bridges:
			var pts: PackedVector2Array = deck.pts
			var middle := pts[pts.size() / 2] * zoom + pan
			view.draw_string(font, middle + Vector2(14, 0), deck.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.85, 0.9, 1.0))
	if layers.places and game.generator is CityGenerator:
		_draw_places(font)
	if layers.bridge:
		for poi: Dictionary in (game.generator.pois() if game.generator is CityGenerator else []):
			if poi.get("kind", "") in ["ferry_terminal", "bridge"]:
				var p: Array = poi.p
				view.draw_string(font, Vector2(p[0], p[1]) * zoom + pan, "~", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.6, 0.8, 1.0))
	if game.waypoint != Vector3.INF:
		var w := _to_screen(game.waypoint)
		view.draw_line(w + Vector2(-8, -8), w + Vector2(8, 8), UiTheme.ACCENT, 3)
		view.draw_line(w + Vector2(-8, 8), w + Vector2(8, -8), UiTheme.ACCENT, 3)
	# Oyuncu: bakis yonunu gosteren ok.
	var p := _to_screen(game.player.global_position)
	var look: Vector3 = game.player.look_direction()
	var dir := Vector2(look.x, look.z).normalized()
	var side := Vector2(-dir.y, dir.x)
	view.draw_colored_polygon(PackedVector2Array([p + dir * 12, p - dir * 7 + side * 7, p - dir * 7 - side * 7]), Color(0.3, 0.7, 1.0))


func _has_map_kit() -> bool:
	for stack: ItemStack in game.inventory.stacks:
		if stack.definition.has_tag("map_tool") or float(stack.definition.effects.get("map_reveal", 0.0)) > 0.0:
			return true
	return false


func _draw_places(font: Font) -> void:
	## Semt adlari (uzaktan) ve kurum isaretleri. Harita Seti yoksa yalniz
	## yakin cevre: kesif hissi korunur, harita "hazir cozum" olmaz.
	var all := _has_map_kit()
	var me := Vector2(game.player.global_position.x, game.player.global_position.z)
	var vis := Rect2(-pan / zoom, view.size / zoom).grow(40.0)
	for poi: Dictionary in (game.generator as CityGenerator).pois():
		var kind := str(poi.get("kind", ""))
		var p := Vector2(float(poi.p[0]), float(poi.p[1]))
		if not vis.has_point(p):
			continue
		var c := p * zoom + pan
		if kind == "district":
			if zoom < 0.9:
				view.draw_string(font, c - Vector2(40, 0), UiTheme.upper(str(poi.name)), HORIZONTAL_ALIGNMENT_LEFT, -1,
					18, Color(1, 1, 1, 0.55))
			continue
		if not POI_STYLE.has(kind) or (not all and p.distance_to(me) > NEAR_POI_M):
			continue
		var style: Array = POI_STYLE[kind]
		view.draw_circle(c, 8.0, Color(0.05, 0.06, 0.07, 0.85))
		view.draw_circle(c, 6.5, style[0])
		view.draw_string(font, c + Vector2(-4, 5), str(style[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.05, 0.05, 0.05))
		if zoom >= 0.5 and str(poi.get("name", "")) != "":
			view.draw_string(font, c + Vector2(11, 5), str(poi.name), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, style[0])


func refresh() -> void:
	if view != null:
		view.queue_redraw()
