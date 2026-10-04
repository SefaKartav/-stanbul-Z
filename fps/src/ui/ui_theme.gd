class_name UiTheme
extends RefCounted
## Tum ekranlarin ortak gorunumu. Tek yerde tanimlanir; ekranlar kendi
## renklerini uydurmaz (tutarsiz arayuz = "yarim kalmis oyun" hissi).
##
## YAZI TIPLERI (assets/fonts, SIL Open Font License 1.1, Turkce tam):
##   * Barlow          -- govde metni, sayilar (okunakli, genis x-yuksekligi)
##   * Barlow Condensed -- basliklar, etiketler, HUD (dar, askeri/teknik ton)
## Font yuklenemezse Godot'un yedek fontuna dusulur: arayuz yine acilir.
##
## TIP VARYASYONLARI (theme_type_variation):
##   PrimaryButton  -- ana eylem (Uret, Devam et): dolu vurgu rengi
##   MenuItem       -- ana menu/duraklatma satiri: saydam, solda vurgu cizgisi
##   RailButton     -- kategori rayi: secili durumda sola dayali vurgu
##   Card           -- PanelContainer icinde ikinci seviye yuzey
##   Inset          -- gomulu, koyu alan (liste, ayrinti)

const BG := Color(0.043, 0.051, 0.063, 0.94)
const PANEL := Color(0.071, 0.082, 0.098, 1.0)
const PANEL_LIGHT := Color(0.118, 0.133, 0.157, 1.0)
const SURFACE := Color(0.098, 0.11, 0.13, 1.0)
const INSET := Color(0.047, 0.055, 0.067, 1.0)
const LINE := Color(0.2, 0.22, 0.25, 1.0)
const LINE_SOFT := Color(1, 1, 1, 0.06)
const ACCENT := Color(0.91, 0.69, 0.3)
const ACCENT_SOFT := Color(0.91, 0.69, 0.3, 0.16)
const TEXT := Color(0.925, 0.914, 0.89)
const TEXT_DIM := Color(0.74, 0.74, 0.72)
const MUTED := Color(0.54, 0.565, 0.6)
const GOOD := Color(0.44, 0.78, 0.5)
const BAD := Color(0.9, 0.36, 0.31)
const INFO := Color(0.42, 0.66, 0.92)
const ON_ACCENT := Color(0.09, 0.07, 0.04)

const FONT_DIR := "res://assets/fonts/"

static var _theme: Theme
static var _fonts: Dictionary = {}


# ---------------------------------------------------------------------------
# Yazi tipleri
# ---------------------------------------------------------------------------
static func _font(file_name: String) -> Font:
	if _fonts.has(file_name):
		return _fonts[file_name]
	var font: Font = null
	var path := FONT_DIR + file_name
	if ResourceLoader.exists(path):
		var loaded := load(path) as FontFile
		if loaded != null:
			loaded.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
			loaded.hinting = TextServer.HINTING_LIGHT
			loaded.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
			loaded.generate_mipmaps = true
			font = loaded
	if font == null:
		font = ThemeDB.fallback_font
	_fonts[file_name] = font
	return font


static func font_body() -> Font:
	return _font("Barlow-Medium.ttf")


static func font_body_regular() -> Font:
	return _font("Barlow-Regular.ttf")


static func font_strong() -> Font:
	return _font("Barlow-SemiBold.ttf")


static func font_heading() -> Font:
	## Basliklar: dar, hafif harf araligi (FontVariation ile).
	if _fonts.has("_heading"):
		return _fonts["_heading"]
	var variation := FontVariation.new()
	variation.base_font = _font("BarlowCondensed-SemiBold.ttf")
	variation.spacing_glyph = 1
	_fonts["_heading"] = variation
	return variation


static func font_display() -> Font:
	## Ana menu basligi gibi buyuk puntolar: kalin, genis aralik.
	if _fonts.has("_display"):
		return _fonts["_display"]
	var variation := FontVariation.new()
	variation.base_font = _font("BarlowCondensed-Bold.ttf")
	variation.spacing_glyph = 4
	_fonts["_display"] = variation
	return variation


static func font_label() -> Font:
	## Kucuk buyuk harfli etiketler (CAN, GOREV...): genis aralik.
	if _fonts.has("_label"):
		return _fonts["_label"]
	var variation := FontVariation.new()
	variation.base_font = _font("BarlowCondensed-SemiBold.ttf")
	variation.spacing_glyph = 2
	_fonts["_label"] = variation
	return variation


# ---------------------------------------------------------------------------
# Kutu yardimcilari
# ---------------------------------------------------------------------------
static func box(bg: Color, radius: int = 4, border: Color = Color.TRANSPARENT, border_width: int = 0,
		margin_h: float = 12.0, margin_v: float = 8.0) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.set_corner_radius_all(radius)
	if border_width > 0:
		b.border_color = border
		b.set_border_width_all(border_width)
	b.content_margin_left = margin_h
	b.content_margin_right = margin_h
	b.content_margin_top = margin_v
	b.content_margin_bottom = margin_v
	b.anti_aliasing = true
	return b


static func _outline_box(border: Color, width: int = 1, radius: int = 4) -> StyleBoxFlat:
	var b := box(Color.TRANSPARENT, radius, border, width)
	b.draw_center = false
	return b


static func _icon(size: int, fill: Color, border: Color, mark: Color = Color.TRANSPARENT, round := false) -> ImageTexture:
	## Onay kutusu / kaydirici tutamagi icin kodla cizilmis kucuk simge
	## (ek dosya gerektirmez). `mark` verilirse ortaya tik isareti cizilir.
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := (size - 1) * 0.5
	var s := float(size) / 20.0
	var tick := [Vector2(5, 10.5) * s, Vector2(8.5, 14) * s, Vector2(15, 6.5) * s]
	for y in size:
		for x in size:
			var col := Color.TRANSPARENT
			if round:
				var d := Vector2(x - c, y - c).length()
				var r := c
				if d <= r - 1.5:
					col = fill
				elif d <= r:
					col = border
					col.a *= clampf(r - d + 0.5, 0.0, 1.0)
			else:
				var edge := mini(mini(x, y), mini(size - 1 - x, size - 1 - y))
				col = border if edge < 2 else fill
				# Kose yuvarlatma
				var corner := Vector2(minf(x, size - 1 - x), minf(y, size - 1 - y))
				if corner.x < 2 and corner.y < 2 and corner.x + corner.y < 2:
					col = Color.TRANSPARENT
				if mark.a > 0.0:
					var p := Vector2(x, y)
					var dist := minf(Geometry2D.get_closest_point_to_segment(p, tick[0], tick[1]).distance_to(p),
						Geometry2D.get_closest_point_to_segment(p, tick[1], tick[2]).distance_to(p))
					var cover := clampf(1.9 * s - dist, 0.0, 1.0)
					if cover > 0.0:
						col = col.lerp(mark, cover)
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


# ---------------------------------------------------------------------------
# Tema
# ---------------------------------------------------------------------------
static func get_theme() -> Theme:
	if _theme != null:
		return _theme
	var theme := Theme.new()
	theme.default_font = font_body()
	theme.default_font_size = 20

	# Paneller
	var panel := box(PANEL, 8, LINE, 1, 22, 18)
	panel.shadow_color = Color(0, 0, 0, 0.45)
	panel.shadow_size = 24
	theme.set_stylebox("panel", "PanelContainer", panel)
	theme.set_type_variation("Card", "PanelContainer")
	theme.set_stylebox("panel", "Card", box(SURFACE, 6, LINE_SOFT, 1, 16, 12))
	theme.set_type_variation("Inset", "PanelContainer")
	theme.set_stylebox("panel", "Inset", box(INSET, 6, LINE, 1, 12, 10))
	theme.set_stylebox("panel", "Panel", box(PANEL, 8, LINE, 1))

	# Etiketler
	theme.set_color("font_color", "Label", TEXT)
	theme.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.0))
	theme.set_constant("line_spacing", "Label", 3)
	theme.set_color("default_color", "RichTextLabel", TEXT)
	theme.set_font("normal_font", "RichTextLabel", font_body())
	theme.set_font("bold_font", "RichTextLabel", font_strong())

	# Dugmeler
	var normal := box(PANEL_LIGHT, 5, LINE, 1, 16, 9)
	var hover := box(PANEL_LIGHT.lightened(0.07), 5, ACCENT.darkened(0.25), 1, 16, 9)
	var pressed := box(ACCENT.darkened(0.35), 5, ACCENT, 1, 16, 9)
	var disabled := box(SURFACE.darkened(0.15), 5, LINE_SOFT, 1, 16, 9)
	for type_name: String in ["Button", "OptionButton", "MenuButton"]:
		theme.set_stylebox("normal", type_name, normal)
		theme.set_stylebox("hover", type_name, hover)
		theme.set_stylebox("pressed", type_name, pressed)
		theme.set_stylebox("hover_pressed", type_name, pressed)
		theme.set_stylebox("disabled", type_name, disabled)
		theme.set_stylebox("focus", type_name, _outline_box(ACCENT, 1, 5))
		theme.set_font("font", type_name, font_strong())
		theme.set_font_size("font_size", type_name, 19)
		theme.set_color("font_color", type_name, TEXT)
		theme.set_color("font_hover_color", type_name, Color.WHITE)
		theme.set_color("font_pressed_color", type_name, Color.WHITE)
		theme.set_color("font_hover_pressed_color", type_name, Color.WHITE)
		theme.set_color("font_focus_color", type_name, TEXT)
		theme.set_color("font_disabled_color", type_name, MUTED.darkened(0.2))
		theme.set_constant("h_separation", type_name, 8)

	theme.set_type_variation("PrimaryButton", "Button")
	theme.set_stylebox("normal", "PrimaryButton", box(ACCENT, 5, ACCENT.lightened(0.15), 1, 22, 11))
	theme.set_stylebox("hover", "PrimaryButton", box(ACCENT.lightened(0.12), 5, ACCENT.lightened(0.3), 1, 22, 11))
	theme.set_stylebox("pressed", "PrimaryButton", box(ACCENT.darkened(0.15), 5, ACCENT, 1, 22, 11))
	theme.set_stylebox("hover_pressed", "PrimaryButton", box(ACCENT.darkened(0.15), 5, ACCENT, 1, 22, 11))
	theme.set_stylebox("disabled", "PrimaryButton", box(ACCENT.darkened(0.62), 5, ACCENT.darkened(0.5), 1, 22, 11))
	for key: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		theme.set_color(key, "PrimaryButton", ON_ACCENT)
	theme.set_color("font_disabled_color", "PrimaryButton", ACCENT.darkened(0.2))
	theme.set_font("font", "PrimaryButton", font_heading())
	theme.set_font_size("font_size", "PrimaryButton", 22)

	theme.set_type_variation("MenuItem", "Button")
	var menu_normal := box(Color(1, 1, 1, 0.0), 0, Color.TRANSPARENT, 0, 22, 12)
	var menu_hover := box(Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.1), 0, Color.TRANSPARENT, 0, 22, 12)
	menu_hover.border_color = ACCENT
	menu_hover.border_width_left = 4
	var menu_pressed := menu_hover.duplicate() as StyleBoxFlat
	menu_pressed.bg_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.2)
	theme.set_stylebox("normal", "MenuItem", menu_normal)
	theme.set_stylebox("hover", "MenuItem", menu_hover)
	theme.set_stylebox("pressed", "MenuItem", menu_pressed)
	theme.set_stylebox("hover_pressed", "MenuItem", menu_pressed)
	theme.set_stylebox("focus", "MenuItem", StyleBoxEmpty.new())
	theme.set_stylebox("disabled", "MenuItem", menu_normal)
	theme.set_font("font", "MenuItem", font_heading())
	theme.set_font_size("font_size", "MenuItem", 28)
	theme.set_color("font_color", "MenuItem", TEXT_DIM)
	theme.set_color("font_hover_color", "MenuItem", Color.WHITE)
	theme.set_color("font_pressed_color", "MenuItem", ACCENT)
	theme.set_color("font_hover_pressed_color", "MenuItem", ACCENT)
	theme.set_color("font_disabled_color", "MenuItem", MUTED.darkened(0.3))

	theme.set_type_variation("RailButton", "Button")
	var rail_normal := box(Color.TRANSPARENT, 4, Color.TRANSPARENT, 0, 14, 8)
	var rail_hover := box(Color(1, 1, 1, 0.04), 4, Color.TRANSPARENT, 0, 14, 8)
	var rail_on := box(ACCENT_SOFT, 4, ACCENT, 0, 14, 8)
	rail_on.border_width_left = 3
	theme.set_stylebox("normal", "RailButton", rail_normal)
	theme.set_stylebox("hover", "RailButton", rail_hover)
	theme.set_stylebox("pressed", "RailButton", rail_on)
	theme.set_stylebox("hover_pressed", "RailButton", rail_on)
	theme.set_stylebox("focus", "RailButton", StyleBoxEmpty.new())
	theme.set_font("font", "RailButton", font_body())
	theme.set_font_size("font_size", "RailButton", 18)
	theme.set_color("font_color", "RailButton", TEXT_DIM)
	theme.set_color("font_hover_color", "RailButton", Color.WHITE)
	theme.set_color("font_pressed_color", "RailButton", ACCENT)
	theme.set_color("font_hover_pressed_color", "RailButton", ACCENT)
	theme.set_constant("align_to_largest_stylebox", "RailButton", 1)

	# Onay kutusu
	var check_off := _icon(20, INSET, LINE.lightened(0.25))
	var check_on := _icon(20, ACCENT, ACCENT, ON_ACCENT)
	for type_name: String in ["CheckBox", "CheckButton"]:
		for state: String in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
			theme.set_stylebox(state, type_name, box(Color.TRANSPARENT, 4, Color.TRANSPARENT, 0, 4, 6) \
				if state != "hover" and state != "hover_pressed" else box(Color(1, 1, 1, 0.04), 4, Color.TRANSPARENT, 0, 4, 6))
		theme.set_color("font_color", type_name, TEXT_DIM)
		theme.set_color("font_hover_color", type_name, Color.WHITE)
		theme.set_color("font_pressed_color", type_name, TEXT)
		theme.set_color("font_hover_pressed_color", type_name, Color.WHITE)
		theme.set_color("font_focus_color", type_name, TEXT)
		theme.set_font_size("font_size", type_name, 18)
		theme.set_constant("h_separation", type_name, 10)
	theme.set_icon("unchecked", "CheckBox", check_off)
	theme.set_icon("checked", "CheckBox", check_on)
	theme.set_icon("unchecked_disabled", "CheckBox", check_off)
	theme.set_icon("checked_disabled", "CheckBox", check_on)

	# Listeler
	theme.set_stylebox("panel", "ItemList", box(INSET, 6, LINE, 1, 6, 6))
	theme.set_stylebox("focus", "ItemList", StyleBoxEmpty.new())
	var item_hover := box(Color(1, 1, 1, 0.045), 4)
	var item_selected := box(ACCENT_SOFT, 4, ACCENT, 0)
	item_selected.border_width_left = 3
	theme.set_stylebox("hovered", "ItemList", item_hover)
	theme.set_stylebox("hovered_selected", "ItemList", item_selected)
	theme.set_stylebox("hovered_selected_focus", "ItemList", item_selected)
	theme.set_stylebox("selected", "ItemList", item_selected)
	theme.set_stylebox("selected_focus", "ItemList", item_selected)
	theme.set_stylebox("cursor", "ItemList", StyleBoxEmpty.new())
	theme.set_stylebox("cursor_unfocused", "ItemList", StyleBoxEmpty.new())
	theme.set_color("font_color", "ItemList", TEXT)
	theme.set_color("font_hovered_color", "ItemList", Color.WHITE)
	theme.set_color("font_selected_color", "ItemList", Color.WHITE)
	theme.set_color("font_hovered_selected_color", "ItemList", Color.WHITE)
	theme.set_color("guide_color", "ItemList", Color(0, 0, 0, 0))
	theme.set_font_size("font_size", "ItemList", 18)
	theme.set_constant("v_separation", "ItemList", 8)
	theme.set_constant("h_separation", "ItemList", 12)
	theme.set_constant("line_separation", "ItemList", 2)

	# Metin girisi
	var line := box(INSET, 5, LINE, 1, 12, 8)
	var line_focus := box(INSET, 5, ACCENT, 1, 12, 8)
	for type_name: String in ["LineEdit", "TextEdit"]:
		theme.set_stylebox("normal", type_name, line)
		theme.set_stylebox("focus", type_name, line_focus)
		theme.set_stylebox("read_only", type_name, line)
		theme.set_color("font_color", type_name, TEXT)
		theme.set_color("font_placeholder_color", type_name, MUTED)
		theme.set_color("caret_color", type_name, ACCENT)
		theme.set_color("selection_color", type_name, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.35))
		theme.set_font_size("font_size", type_name, 19)

	# Acilir menu / ipucu
	var popup := box(PANEL_LIGHT, 6, LINE, 1, 6, 6)
	popup.shadow_color = Color(0, 0, 0, 0.5)
	popup.shadow_size = 12
	theme.set_stylebox("panel", "PopupMenu", popup)
	theme.set_stylebox("hover", "PopupMenu", box(ACCENT_SOFT, 4))
	theme.set_color("font_color", "PopupMenu", TEXT_DIM)
	theme.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	theme.set_font_size("font_size", "PopupMenu", 18)
	theme.set_constant("v_separation", "PopupMenu", 10)
	theme.set_stylebox("panel", "TooltipPanel", box(Color(0.06, 0.07, 0.085, 0.98), 5, LINE, 1, 12, 8))
	theme.set_color("font_color", "TooltipLabel", TEXT)
	theme.set_font_size("font_size", "TooltipLabel", 17)

	# Ilerleme cubugu
	theme.set_stylebox("background", "ProgressBar", box(INSET, 4, LINE, 1, 0, 0))
	var fill := box(ACCENT, 4)
	theme.set_stylebox("fill", "ProgressBar", fill)
	theme.set_color("font_color", "ProgressBar", TEXT)
	theme.set_font_size("font_size", "ProgressBar", 14)

	# Kaydirici
	var track := box(INSET, 3, LINE, 1, 0, 3)
	var area := box(ACCENT.darkened(0.1), 3)
	area.content_margin_top = 3
	area.content_margin_bottom = 3
	for type_name: String in ["HSlider", "VSlider"]:
		theme.set_stylebox("slider", type_name, track)
		theme.set_stylebox("grabber_area", type_name, area)
		theme.set_stylebox("grabber_area_highlight", type_name, box(ACCENT, 3))
		theme.set_icon("grabber", type_name, _icon(18, TEXT, ACCENT, Color.TRANSPARENT, true))
		theme.set_icon("grabber_highlight", type_name, _icon(18, Color.WHITE, ACCENT, Color.TRANSPARENT, true))

	# Kaydirma cubugu
	for type_name: String in ["VScrollBar", "HScrollBar"]:
		theme.set_stylebox("scroll", type_name, box(Color(1, 1, 1, 0.02), 4, Color.TRANSPARENT, 0, 3, 3))
		theme.set_stylebox("scroll_focus", type_name, box(Color(1, 1, 1, 0.02), 4, Color.TRANSPARENT, 0, 3, 3))
		theme.set_stylebox("grabber", type_name, box(Color(1, 1, 1, 0.16), 4, Color.TRANSPARENT, 0, 3, 3))
		theme.set_stylebox("grabber_highlight", type_name, box(Color(1, 1, 1, 0.28), 4, Color.TRANSPARENT, 0, 3, 3))
		theme.set_stylebox("grabber_pressed", type_name, box(ACCENT.darkened(0.2), 4, Color.TRANSPARENT, 0, 3, 3))

	# Ayiricilar
	var sep := StyleBoxLine.new()
	sep.color = LINE
	sep.thickness = 1
	theme.set_stylebox("separator", "HSeparator", sep)
	theme.set_constant("separation", "HSeparator", 12)
	var vsep := StyleBoxLine.new()
	vsep.color = LINE
	vsep.thickness = 1
	vsep.vertical = true
	theme.set_stylebox("separator", "VSeparator", vsep)

	_theme = theme
	return theme


# ---------------------------------------------------------------------------
# Kurucular
# ---------------------------------------------------------------------------
static func upper(text: String) -> String:
	## Turkce buyuk harf: i -> İ, ı -> I (String.to_upper yerel ayar bilmez).
	return text.replace("i", "İ").replace("ı", "I").to_upper()



static func label(text: String, size: int = 20, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	# Kisa etiketler (satir icindeki "Adet:" gibi) kaydirilmaz: kaydirmali
	# etiket bir HBox icinde sifir genislige buzulup dikey harflere donusur.
	if text.length() > 32 or text.contains("\n"):
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func heading(text: String, size: int = 26, color: Color = TEXT) -> Label:
	## Dar, buyuk harfli baslik.
	var l := label(upper(text), size, color)
	l.add_theme_font_override("font", font_heading())
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	return l


static func eyebrow(text: String, color: Color = MUTED) -> Label:
	## Bolum ustu kucuk etiket ("GEREKSINIMLER").
	var l := label(upper(text), 15, color)
	l.add_theme_font_override("font", font_label())
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	return l


static func section(text: String) -> Control:
	## Etiket + ince cizgi: ekran icindeki bolum basligi.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var l := eyebrow(text, ACCENT)
	row.add_child(l)
	var line := HSeparator.new()
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(line)
	return row


static func button(text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(callback)
	b.focus_mode = Control.FOCUS_NONE
	return b


static func primary_button(text: String, callback: Callable) -> Button:
	var b := button(text, callback)
	b.theme_type_variation = "PrimaryButton"
	return b


static func menu_item(text: String, callback: Callable) -> Button:
	var b := button(upper(text), callback)
	b.theme_type_variation = "MenuItem"
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	return b


static func card(variation: String = "Card") -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = variation
	return p


static func chip(text: String, color: Color = ACCENT, size: int = 15) -> PanelContainer:
	## Kucuk rozet: "T2", "TEZGAH", "ESC".
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(Color(color.r, color.g, color.b, 0.14), 4,
		Color(color.r, color.g, color.b, 0.45), 1, 8, 2))
	var l := label(upper(text), size, color)
	l.add_theme_font_override("font", font_label())
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	p.add_child(l)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return p


static func key_hint(key: String, text: String) -> HBoxContainer:
	## Tus ipucu: [ESC] Kapat
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var cap := PanelContainer.new()
	var cap_box := box(PANEL_LIGHT, 4, LINE.lightened(0.2), 1, 8, 1)
	cap_box.border_width_bottom = 2
	cap.add_theme_stylebox_override("panel", cap_box)
	var k := label(upper(key), 15, TEXT)
	k.add_theme_font_override("font", font_label())
	cap.add_child(k)
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(cap)
	row.add_child(label(text, 17, MUTED))
	return row
