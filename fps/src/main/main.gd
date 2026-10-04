extends Node
## Uygulama koku: ana menu <-> oyun gecisi.
##
## Icerik hataliysa oyun ACILMAZ ve hatalar listelenir (icerik = veri
## kurali). Kayit yuklemek oyunu sahneden kaldirip YENIDEN kurar: yarim
## kalmis dunya durumu yeni kaydin ustune karismaz.

const GAME_SCRIPT := preload("res://src/game/game.gd")

var game: Node
var menu: Control
var saves := SaveSystem.new()
var _error := ""


func _ready() -> void:
	if not Content.ok():
		_show_content_errors()
		return
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--menu-shot="):
			# Arayuz incelemesi: ana menunun goruntusunu al ve cik.
			show_menu()
			var path := arg.trim_prefix("--menu-shot=")
			get_tree().create_timer(1.0).timeout.connect(func() -> void:
				get_viewport().get_texture().get_image().save_png(path)
				get_tree().quit())
			return
		if arg.begins_with("--site") or arg.begins_with("--shot") or arg.begins_with("--load"):
			start_game("")
			return
	show_menu()


func show_error(text: String) -> void:
	_error = text


func show_menu() -> void:
	get_tree().paused = false
	if game != null:
		game.queue_free()
		game = null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if menu != null:
		menu.queue_free()
	var layer := CanvasLayer.new()
	add_child(layer)
	menu = _build_menu()
	layer.add_child(menu)


func start_game(load_slot: String) -> void:
	if menu != null:
		menu.get_parent().queue_free()
		menu = null
	if game != null:
		game.queue_free()
	game = GAME_SCRIPT.new()
	game.name = "Game"
	game.load_slot = load_slot
	game.request_main_menu.connect(func() -> void: show_menu.call_deferred())
	game.request_restart.connect(func(slot: String) -> void: start_game.call_deferred(slot))
	add_child(game)


const MENU_TIPS := [
	"Gürültü zombileri çeker: kapıyı kırmak yerine maymuncuk kullan.",
	"Kirli su hasta eder. Arıtmadan içme; bozulan yiyecekler de risklidir.",
	"Üretim dünya akarken sürer. Uzun işleri güvenli bir üste başlat.",
	"Yedinci gece büyük dalga gelir. Barikat ve mühimmatı önceden hazırla.",
	"Araç yakıtı sınırlı: uzun sefer öncesi dönüş yolunu planla.",
]


func _build_menu() -> Control:
	var root := Control.new()
	root.theme = UiTheme.get_theme()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Arka plan: koyu dikey gecis + sicak ufuk isigi + kenar karartmasi.
	var bg := TextureRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	grad.colors = PackedColorArray([Color(0.05, 0.06, 0.08), Color(0.075, 0.07, 0.07), Color(0.16, 0.1, 0.06)])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0.5, 0.0)
	tex.fill_to = Vector2(0.5, 1.0)
	tex.width = 16
	tex.height = 256
	bg.texture = tex
	root.add_child(bg)
	var glow := TextureRect.new()
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	var glow_grad := Gradient.new()
	glow_grad.colors = PackedColorArray([Color(0.91, 0.6, 0.25, 0.22), Color(0.91, 0.6, 0.25, 0.0)])
	var glow_tex := GradientTexture2D.new()
	glow_tex.gradient = glow_grad
	glow_tex.fill = GradientTexture2D.FILL_RADIAL
	glow_tex.fill_from = Vector2(0.78, 0.85)
	glow_tex.fill_to = Vector2(0.78, 0.15)
	glow.texture = glow_tex
	root.add_child(glow)
	var vignette := TextureRect.new()
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	var vig_grad := Gradient.new()
	vig_grad.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	vig_grad.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0.25), Color(0, 0, 0, 0.75)])
	var vig_tex := GradientTexture2D.new()
	vig_tex.gradient = vig_grad
	vig_tex.fill = GradientTexture2D.FILL_RADIAL
	vig_tex.fill_from = Vector2(0.5, 0.5)
	vig_tex.fill_to = Vector2(1.1, 1.1)
	vignette.texture = vig_tex
	root.add_child(vignette)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 120)
	margin.add_theme_constant_override("margin_right", 120)
	margin.add_theme_constant_override("margin_top", 110)
	margin.add_theme_constant_override("margin_bottom", 64)
	root.add_child(margin)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 80)
	margin.add_child(columns)

	# Sol: marka + menu
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 620
	left.add_theme_constant_override("separation", 6)
	columns.add_child(left)
	var eyebrow_row := HBoxContainer.new()
	eyebrow_row.add_theme_constant_override("separation", 12)
	left.add_child(eyebrow_row)
	var mark := ColorRect.new()
	mark.color = UiTheme.ACCENT
	mark.custom_minimum_size = Vector2(36, 3)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	eyebrow_row.add_child(mark)
	eyebrow_row.add_child(UiTheme.eyebrow("Hayatta kalma · İnşa · Koloni", UiTheme.ACCENT))
	var title := UiTheme.label("İSTANBUL-Z", 132, UiTheme.TEXT)
	title.add_theme_font_override("font", UiTheme.font_display())
	title.add_theme_constant_override("line_spacing", -20)
	left.add_child(title)
	var tagline := UiTheme.label("Şehir düştü. Surların ardında hâlâ bir hayat kurulabilir.", 22, UiTheme.TEXT_DIM)
	tagline.autowrap_mode = TextServer.AUTOWRAP_OFF
	left.add_child(tagline)
	var gap := Control.new()
	gap.custom_minimum_size.y = 42
	left.add_child(gap)

	var slots := saves.list_slots()
	if not slots.is_empty():
		var latest: Dictionary = slots[0]
		left.add_child(UiTheme.menu_item("Devam et", start_game.bind(str(latest.slot))))
	left.add_child(UiTheme.menu_item("Yeni oyun", start_game.bind("")))
	for entry: Dictionary in slots.slice(1, 4):
		var load_button := UiTheme.menu_item("Yükle · %s" % entry.slot, start_game.bind(str(entry.slot)))
		load_button.add_theme_font_size_override("font_size", 22)
		load_button.tooltip_text = "Gün %d · %s" % [entry.day, entry.clock]
		left.add_child(load_button)
	left.add_child(UiTheme.menu_item("Çıkış", func() -> void: get_tree().quit()))
	if _error != "":
		var err := UiTheme.card()
		err.add_theme_stylebox_override("panel", UiTheme.box(Color(UiTheme.BAD.r, UiTheme.BAD.g, UiTheme.BAD.b, 0.12), 6,
			UiTheme.BAD, 1, 14, 10))
		err.add_child(UiTheme.label(_error, 18, UiTheme.BAD.lightened(0.2)))
		left.add_child(err)
		_error = ""
	var push := Control.new()
	push.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(push)
	left.add_child(UiTheme.label("Sürüm %s  ·  Harita verisi © OpenStreetMap katkıcıları, ODbL  ·  Godot Engine (MIT)  ·  Barlow (OFL)"
		% ProjectSettings.get_setting("application/config/version", ""), 14, UiTheme.MUTED))

	# Sag: son kayit + ipucu kartlari
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.alignment = BoxContainer.ALIGNMENT_END
	right.add_theme_constant_override("separation", 16)
	columns.add_child(right)
	var holder := HBoxContainer.new()
	holder.alignment = BoxContainer.ALIGNMENT_END
	right.add_child(holder)
	var cards := VBoxContainer.new()
	cards.custom_minimum_size.x = 440
	cards.add_theme_constant_override("separation", 16)
	holder.add_child(cards)
	if not slots.is_empty():
		var latest: Dictionary = slots[0]
		var save_card := UiTheme.card()
		cards.add_child(save_card)
		var sv := VBoxContainer.new()
		sv.add_theme_constant_override("separation", 6)
		save_card.add_child(sv)
		sv.add_child(UiTheme.eyebrow("Son kayıt", UiTheme.ACCENT))
		sv.add_child(UiTheme.heading("Gün %d · %s" % [latest.day, latest.clock], 34, UiTheme.TEXT))
		sv.add_child(UiTheme.label("Kayıt yuvası: %s" % latest.slot, 17, UiTheme.MUTED))
	var legacy := saves.legacy_slots()
	if not legacy.is_empty():
		var legacy_card := UiTheme.card()
		cards.add_child(legacy_card)
		var lv := VBoxContainer.new()
		legacy_card.add_child(lv)
		lv.add_child(UiTheme.eyebrow("Eski kayıtlar", UiTheme.MUTED))
		lv.add_child(UiTheme.label("Eski 2D kayıtlar bulundu (%s). Harita ve 3D dönüşümü uyumsuz olduğu için açılmaz; dosyalar korunuyor."
			% ", ".join(legacy), 16, UiTheme.TEXT_DIM))
	var tip_card := UiTheme.card()
	cards.add_child(tip_card)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 6)
	tip_card.add_child(tv)
	tv.add_child(UiTheme.eyebrow("Hayatta kalma notu", UiTheme.MUTED))
	var tip := UiTheme.label(MENU_TIPS[randi() % MENU_TIPS.size()], 18, UiTheme.TEXT_DIM)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tv.add_child(tip)
	return root


func _show_content_errors() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(panel)
	var label := RichTextLabel.new()
	label.text = "ICERIK DOGRULAMA BASARISIZ -- oyun baslatilamaz.\n\n" + "\n".join(Content.errors)
	panel.add_child(label)
