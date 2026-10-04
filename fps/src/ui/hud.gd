class_name Hud
extends Control
## Oyun ici gosterge: can/enerji/dayaniklilik, silah ve mermi, saat,
## etkilesim ipucu, ilerleme cubugu, mesaj akisi.
##
## Olcek: tum olculer 1920x1080 tabanina gore yazilir; proje ayari
## (stretch canvas_items) ekran boyutuna gore olcekler.
##
## GORSEL DIL: yari saydam koyu kartlar (ince kenar, yuvarlatilmis kose),
## dar buyuk harfli etiketler (Barlow Condensed), sayilar kalin Barlow.
## Can cubugunda son hasar bir "hayalet" iz olarak yavasca erir; %10
## centikler olcek verir. Etkilesim ipucundaki [E] gibi tuslar tus kapagi
## olarak cizilir.

const PANEL := Color(0.035, 0.043, 0.055, 0.72)
const PANEL_EDGE := Color(1, 1, 1, 0.07)
const TRACK := Color(1, 1, 1, 0.07)
const ACCENT := Color(0.91, 0.69, 0.3)
const RED := Color(0.9, 0.3, 0.26)
const GREEN := Color(0.46, 0.8, 0.52)
const BLUE := Color(0.42, 0.66, 0.94)
const MUTED_COLOR := Color(0.68, 0.7, 0.73)
const TEXT := Color(0.95, 0.94, 0.91)
const HEALTH := Color(0.84, 0.27, 0.23)
const FOOD := Color(0.88, 0.64, 0.3)
const WATER := Color(0.36, 0.66, 0.95)

var health_ratio := 1.0
var energy_ratio := 1.0
var stamina_ratio := 1.0
var stamina_cap := 1.0           # aclik/susuzlukta nefes tavani (cubukta tarali bolge)
var satiety := 1.0               # kisisel tokluk 0..1
var hydration := 1.0             # kisisel hidrasyon 0..1
var objective := ""              # aktif gorev adimi (J: gunluk)
var _icons: Dictionary = {}
var weapon_name := ""
var ammo_text := ""
var ammo_low := false
var durability_ratio := -1.0
var clock_text := ""
var day_text := ""
var wave_text := ""
var region_text := ""
var prompt := ""
var progress := -1.0
var progress_label := ""
var statuses := PackedStringArray()
var slots: Array = []            # [{name, active, icon_id?}]
var vehicle: Dictionary = {}     # suruste: {speed, gear, fuel, fuel_text, condition, hint, warning}
var damage_flash := 0.0
var damage_direction := 0.0
var heading := -1.0              # pusula (derece, 0 = kuzey); -1 = pusula yok
var power_text := ""             # usteyken elektrik ozeti
var _messages: Array = []        # [{text, color, time}]
var _font: Font                  # govde (Barlow Medium)
var _strong: Font                # sayilar (Barlow SemiBold)
var _label: Font                 # etiketler (Barlow Condensed, aralikli)
var _heading: Font               # basliklar (Barlow Condensed)
var _health_ghost := 1.0         # hasar izi: gercek degerin arkasindan erir
var _boxes: Dictionary = {}
var _slot_icons: Dictionary = {} # icon_id -> Texture2D (null da onbellege alinir)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_font = UiTheme.font_body()
	_strong = UiTheme.font_strong()
	_label = UiTheme.font_label()
	_heading = UiTheme.font_heading()
	for name: String in ["satiety", "hydration", "mission", "stamina"]:
		_icons[name] = AssetLibrary.ui_icon(name)


func message(text: String, color: Color = Color(0.92, 0.92, 0.9)) -> void:
	_messages.append({"text": text, "color": color, "time": 5.0})
	while _messages.size() > 6:
		_messages.pop_front()


func hurt(amount: float, direction_angle: float) -> void:
	damage_flash = clampf(damage_flash + amount / 30.0, 0.0, 1.0)
	damage_direction = direction_angle


func _process(delta: float) -> void:
	for entry: Dictionary in _messages:
		entry.time -= delta
	_messages = _messages.filter(func(e: Dictionary) -> bool: return e.time > 0.0)
	damage_flash = maxf(0.0, damage_flash - delta * 1.2)
	if health_ratio >= _health_ghost:
		_health_ghost = health_ratio
	else:
		_health_ghost = maxf(health_ratio, _health_ghost - delta * 0.35)
	queue_redraw()


# ---------------------------------------------------------------------------
# Cizim yardimcilari
# ---------------------------------------------------------------------------
func _box(key: String, bg: Color, radius: int, edge := Color.TRANSPARENT) -> StyleBoxFlat:
	## Kutular onbellege alinir: her karede yeni StyleBox uretilmez.
	var id := "%s|%s|%d|%s" % [key, bg.to_html(), radius, edge.to_html()]
	if _boxes.has(id):
		return _boxes[id]
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.set_corner_radius_all(radius)
	b.anti_aliasing = true
	if edge.a > 0.0:
		b.border_color = edge
		b.set_border_width_all(1)
	_boxes[id] = b
	return b


func _panel(rect: Rect2, radius := 8) -> void:
	draw_style_box(_box("panel", PANEL, radius, PANEL_EDGE), rect)


func _fill(rect: Rect2, color: Color, radius := 3) -> void:
	if rect.size.x < 1.0:
		return
	draw_style_box(_box("fill", color, mini(radius, int(rect.size.x * 0.5))), rect)


func _text(text: String, position: Vector2, size: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT,
		width := -1.0, font: Font = null) -> void:
	## Kart ICINDEKI metin: yumusak golge yeter.
	var f := font if font != null else _font
	draw_string(f, position + Vector2(0, 2), text, align, width, size, Color(0, 0, 0, 0.55 * color.a))
	draw_string(f, position, text, align, width, size, color)


func _free_text(text: String, position: Vector2, size: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT,
		width := -1.0, font: Font = null) -> void:
	## Kart DISINDAKI metin (sahne ustunde): ince kontur okunurluk saglar.
	var f := font if font != null else _font
	draw_string_outline(f, position, text, align, width, size, 5, Color(0, 0, 0, 0.7 * color.a))
	draw_string(f, position, text, align, width, size, color)


func _caps(text: String, position: Vector2, size: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	_text(UiTheme.upper(text), position, size, color, align, width, _label)


func _meter(rect: Rect2, ratio: float, color: Color, ticks := 0, ghost := -1.0) -> void:
	## Yuvarlak uclu dolum cubugu; istege bagli centik ve hasar izi.
	var radius := int(rect.size.y * 0.5)
	_fill(rect, TRACK, radius)
	var r := clampf(ratio, 0.0, 1.0)
	if ghost > r + 0.002:
		_fill(Rect2(rect.position, Vector2(rect.size.x * clampf(ghost, 0.0, 1.0), rect.size.y)),
			Color(1, 0.86, 0.72, 0.55), radius)
	_fill(Rect2(rect.position, Vector2(rect.size.x * r, rect.size.y)), color, radius)
	# Ust parlaklik: duz renk yerine hafif hacim.
	if r > 0.02 and rect.size.y >= 8:
		draw_rect(Rect2(rect.position + Vector2(radius, 1), Vector2(maxf(0.0, rect.size.x * r - radius * 2), 1)),
			Color(1, 1, 1, 0.18))
	for i in range(1, ticks):
		var x := rect.position.x + rect.size.x * float(i) / ticks
		draw_line(Vector2(x, rect.position.y + 1), Vector2(x, rect.end.y - 1), Color(0, 0, 0, 0.35), 1.0)


func _keycap(key: String, position: Vector2, size: int) -> float:
	## Tus kapagi cizer, genisligini dondurur. `position` taban cizgisi.
	var w := maxf(_label.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 18.0, size * 1.5)
	var h := size * 1.45
	var rect := Rect2(Vector2(position.x, position.y - h * 0.78), Vector2(w, h))
	draw_style_box(_box("cap_shadow", Color(0, 0, 0, 0.55), 5), Rect2(rect.position + Vector2(0, 3), rect.size))
	draw_style_box(_box("cap", Color(0.93, 0.92, 0.88, 0.96), 5), rect)
	draw_string(_label, Vector2(rect.position.x, position.y - 1), key, HORIZONTAL_ALIGNMENT_CENTER, w, size,
		Color(0.08, 0.08, 0.1))
	return w


# ---------------------------------------------------------------------------
# Cizim
# ---------------------------------------------------------------------------
func _draw() -> void:
	var s := size
	# Hasar kenarligi: vurus yonune gore kirmizi ton (yumusak gecisli).
	if damage_flash > 0.01:
		for i in 6:
			var a := damage_flash * 0.09 * (6 - i) / 6.0
			var c := Color(0.7, 0.05, 0.03, a)
			var w := 14.0 * (i + 1)
			draw_rect(Rect2(Vector2.ZERO, Vector2(s.x, w * 0.5)), c)
			draw_rect(Rect2(Vector2(0, s.y - w * 0.5), Vector2(s.x, w * 0.5)), c)
			draw_rect(Rect2(Vector2.ZERO, Vector2(w * 0.5, s.y)), c)
			draw_rect(Rect2(Vector2(s.x - w * 0.5, 0), Vector2(w * 0.5, s.y)), c)
		var center := s * 0.5
		var dir := Vector2(sin(damage_direction), -cos(damage_direction))
		var tip := center + dir * 150.0
		var side := Vector2(-dir.y, dir.x) * 26.0
		draw_colored_polygon(PackedVector2Array([tip, center + dir * 118.0 + side, center + dir * 118.0 - side]),
			Color(0.9, 0.12, 0.08, damage_flash))

	_draw_vitals(s)
	if objective != "":
		_draw_objective()
	if not vehicle.is_empty():
		_draw_vehicle(s)
	else:
		_draw_weapon(s)
	_draw_top_and_center(s)


func _draw_vitals(s: Vector2) -> void:
	## Sol alt kart: tokluk/su, can, enerji/nefes.
	var w := 372.0
	var h := 176.0
	var origin := Vector2(32, s.y - 32 - h)
	_panel(Rect2(origin, Vector2(w, h)))
	var x := origin.x + 18
	var inner := w - 36

	# Ihtiyaclar (ikonlu, esik altinda yanip soner)
	var half := (inner - 16) * 0.5
	_need(Rect2(Vector2(x, origin.y + 16), Vector2(half, 34)), satiety, FOOD, "Tokluk", "satiety")
	_need(Rect2(Vector2(x + half + 16, origin.y + 16), Vector2(half, 34)), hydration, WATER, "Su", "hydration")

	# Can
	var hy := origin.y + 76
	_caps("Can", Vector2(x, hy + 14), 16, MUTED_COLOR)
	var low := health_ratio < 0.3
	var pulse := 0.65 + 0.35 * sin(Time.get_ticks_msec() * 0.008) if low else 1.0
	_text("%d" % int(round(health_ratio * 100)), Vector2(x, hy + 16), 24, (RED if low else TEXT) * Color(1, 1, 1, pulse),
		HORIZONTAL_ALIGNMENT_RIGHT, inner, _strong)
	_meter(Rect2(Vector2(x, hy + 24), Vector2(inner, 12)), health_ratio, RED if low else HEALTH, 10, _health_ghost)

	# Enerji / Nefes
	var ey := origin.y + 132
	_caps("Enerji", Vector2(x, ey + 10), 14, MUTED_COLOR)
	_text("%d" % int(energy_ratio * 100), Vector2(x, ey + 10), 15, TEXT, HORIZONTAL_ALIGNMENT_RIGHT, half, _strong)
	_meter(Rect2(Vector2(x, ey + 18), Vector2(half, 6)), energy_ratio, BLUE)
	var nx := x + half + 16
	_caps("Nefes", Vector2(nx, ey + 10), 14, MUTED_COLOR)
	_text("%d" % int(stamina_ratio * 100), Vector2(nx, ey + 10), 15, TEXT, HORIZONTAL_ALIGNMENT_RIGHT, half, _strong)
	var nrect := Rect2(Vector2(nx, ey + 18), Vector2(half, 6))
	_meter(nrect, stamina_ratio, GREEN)
	if stamina_cap < 0.999:
		# Aclik/susuzluk nefes tavanini kisti: ulasilamayan kisim tarali.
		var cap_x := nrect.position.x + nrect.size.x * stamina_cap
		var blocked := Rect2(Vector2(cap_x, nrect.position.y), Vector2(nrect.end.x - cap_x, nrect.size.y))
		_fill(blocked, Color(0.55, 0.12, 0.1, 0.75), 3)
		var hx := blocked.position.x
		while hx < blocked.end.x:
			draw_line(Vector2(hx, blocked.end.y), Vector2(minf(hx + 5, blocked.end.x), blocked.position.y), Color(0, 0, 0, 0.45), 1.0)
			hx += 5.0

	# Durumlar: kartin ustunde rozetler
	if not statuses.is_empty():
		var sx := origin.x
		for status: String in statuses:
			var label := status
			var tw := _heading.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x + 20
			var rect := Rect2(Vector2(sx, origin.y - 34), Vector2(tw, 26))
			draw_style_box(_box("status_base", PANEL, 5), rect)
			draw_style_box(_box("status", Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.16), 5, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.5)), rect)
			draw_string(_heading, rect.position + Vector2(10, 19), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, ACCENT)
			sx += tw + 6


func _need(rect: Rect2, ratio: float, color: Color, label: String, icon_name: String) -> void:
	var warn := ratio <= 0.25
	var fill_color := RED if ratio <= 0.1 else color
	if warn and int(Time.get_ticks_msec() / 400) % 2 == 1:
		fill_color = fill_color.darkened(0.4)
	var icon: Texture2D = _icons.get(icon_name)
	var text_x := rect.position.x
	if icon != null:
		draw_style_box(_box("need_icon", Color(color.r, color.g, color.b, 0.16), 6), Rect2(rect.position, Vector2(34, 34)))
		draw_texture_rect(icon, Rect2(rect.position + Vector2(5, 5), Vector2(24, 24)), false)
		text_x += 44
	var tw := rect.end.x - text_x
	_caps(label, Vector2(text_x, rect.position.y + 14), 14, MUTED_COLOR)
	_text("%d" % int(ratio * 100), Vector2(text_x, rect.position.y + 14), 16, RED if warn else TEXT,
		HORIZONTAL_ALIGNMENT_RIGHT, tw, _strong)
	_meter(Rect2(Vector2(text_x, rect.position.y + 24), Vector2(tw, 7)), ratio, fill_color)


func _draw_objective() -> void:
	## Sol ust: aktif gorev karti.
	var icon: Texture2D = _icons.get("mission")
	var text_w := minf(_font.get_string_size(objective, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x, 620.0)
	var rect := Rect2(Vector2(32, 32), Vector2(text_w + (86 if icon != null else 44), 70))
	_panel(rect)
	draw_rect(Rect2(rect.position + Vector2(0, 12), Vector2(3, rect.size.y - 24)), ACCENT)
	var x := rect.position.x + 20
	if icon != null:
		draw_texture_rect(icon, Rect2(Vector2(x, rect.position.y + 20), Vector2(30, 30)), false)
		x += 42
	_caps("Görev", Vector2(x, rect.position.y + 26), 14, ACCENT)
	_text(objective, Vector2(x, rect.position.y + 52), 20, TEXT, HORIZONTAL_ALIGNMENT_LEFT, 620)


func _draw_vehicle(s: Vector2) -> void:
	## Alt orta arac gostergesi: buyuk hiz, vites, yakit ve saglamlik cubugu.
	## Yolu kapatmasin diye ekranin alt kenarinda; renkler esik altinda kirmizi.
	var box := Rect2(Vector2(s.x * 0.5 - 280, s.y - 150), Vector2(560, 118))
	_panel(box, 10)
	_text(str(vehicle.speed), box.position + Vector2(20, 74), 64, TEXT, HORIZONTAL_ALIGNMENT_RIGHT, 130, _heading)
	_caps("km/sa", box.position + Vector2(158, 74), 16, MUTED_COLOR)
	var gear := str(vehicle.gear)
	var gear_rect := Rect2(box.position + Vector2(158, 18), Vector2(44, 32))
	draw_style_box(_box("gear", Color(1, 1, 1, 0.06), 5, Color(1, 1, 1, 0.14)), gear_rect)
	draw_string(_heading, gear_rect.position + Vector2(0, 25), gear, HORIZONTAL_ALIGNMENT_CENTER, 44, 24,
		RED if gear == "G" else ACCENT)
	_caps({"G": "geri", "N": "boş", "I": "ileri"}.get(gear, ""), box.position + Vector2(158, 100), 14, MUTED_COLOR)
	var fuel: float = vehicle.fuel
	var condition: float = vehicle.condition
	var bx := box.position.x + 250
	var bw := 290.0
	_caps("Yakıt", Vector2(bx, box.position.y + 34), 14, MUTED_COLOR)
	_text(str(vehicle.fuel_text), Vector2(bx, box.position.y + 34), 16, TEXT, HORIZONTAL_ALIGNMENT_RIGHT, bw, _strong)
	_meter(Rect2(Vector2(bx, box.position.y + 42), Vector2(bw, 9)), fuel, RED if fuel < 0.15 else ACCENT, 4)
	_caps("Sağlamlık", Vector2(bx, box.position.y + 76), 14, MUTED_COLOR)
	_text("%d%%" % int(condition * 100.0), Vector2(bx, box.position.y + 76), 16, TEXT, HORIZONTAL_ALIGNMENT_RIGHT, bw, _strong)
	_meter(Rect2(Vector2(bx, box.position.y + 84), Vector2(bw, 9)), condition, RED if condition < 0.25 else GREEN, 4)
	var warning := str(vehicle.get("warning", ""))
	if warning != "":
		_caps(warning, Vector2(bx, box.position.y + 110), 14, RED)
	_free_text(str(vehicle.hint), Vector2(s.x * 0.5 - 400, box.position.y - 16), 17, Color(1, 1, 1, 0.85),
		HORIZONTAL_ALIGNMENT_CENTER, 800)


func _draw_weapon(s: Vector2) -> void:
	## Sag alt: silah karti ve hizli erisim yuvalari.
	var w := 372.0
	var card := Rect2(Vector2(s.x - 32 - w, s.y - 32 - 108), Vector2(w, 108))
	_panel(card)
	var x := card.position.x + 20
	var inner := w - 40
	# Esya adlari veriden gelir: buyuk harfe cevrilmez (Turkce harf eslemesi
	# veride garanti degil), dar fontla yazilir.
	_text(weapon_name, Vector2(x, card.position.y + 32), 20, MUTED_COLOR, HORIZONTAL_ALIGNMENT_LEFT, inner, _heading)
	var parts := ammo_text.split(" / ")
	if parts.size() == 2 and parts[0].is_valid_int():
		# "12 / 48": sarjor buyuk, yedek kucuk.
		var reserve := " / " + parts[1]
		var rw := _strong.get_string_size(reserve, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
		_text(reserve, Vector2(card.end.x - 20 - rw, card.position.y + 84), 24, MUTED_COLOR, HORIZONTAL_ALIGNMENT_LEFT, -1, _strong)
		_text(parts[0], Vector2(x, card.position.y + 86), 56, RED if ammo_low else TEXT,
			HORIZONTAL_ALIGNMENT_RIGHT, inner - rw - 6, _heading)
	elif ammo_text != "":
		_text(ammo_text, Vector2(x, card.position.y + 80), 30, ACCENT, HORIZONTAL_ALIGNMENT_RIGHT, inner, _heading)
	if durability_ratio >= 0.0:
		_meter(Rect2(Vector2(x, card.end.y - 12), Vector2(inner, 4)), durability_ratio,
			RED if durability_ratio < 0.2 else Color(0.85, 0.85, 0.82, 0.8))

	# Yuvalar: kartin ustunde kareler (ikon + numara)
	if slots.is_empty():
		return
	var gap := 8.0
	var size_px := minf(64.0, (w - gap * (slots.size() - 1)) / slots.size())
	var sx := card.end.x - (size_px * slots.size() + gap * (slots.size() - 1))
	var sy := card.position.y - 12 - size_px
	for i in slots.size():
		var slot: Dictionary = slots[i]
		var rect := Rect2(Vector2(sx + i * (size_px + gap), sy), Vector2(size_px, size_px))
		var active: bool = slot.active
		draw_style_box(_box("slot", PANEL if not active else Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.2), 7,
			ACCENT if active else PANEL_EDGE), rect)
		var icon := _slot_icon(str(slot.get("icon_id", "")))
		if icon != null:
			draw_texture_rect(icon, rect.grow(-8), false, Color(1, 1, 1, 1.0 if active else 0.8))
		elif str(slot.name) != "":
			draw_string(_label, rect.position + Vector2(0, rect.size.y * 0.62), UiTheme.upper(str(slot.name)).left(6),
				HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 13, TEXT)
		draw_string(_label, rect.position + Vector2(6, 16), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
			ACCENT if active else MUTED_COLOR)


func _slot_icon(icon_id: String) -> Texture2D:
	if icon_id == "":
		return null
	if not _slot_icons.has(icon_id):
		_slot_icons[icon_id] = AssetLibrary.icon(icon_id)
	return _slot_icons[icon_id]


func _draw_top_and_center(s: Vector2) -> void:
	# Ust orta: saat + gun karti, altinda dalga rozeti
	var clock_w := 300.0
	var clock := Rect2(Vector2(s.x * 0.5 - clock_w * 0.5, 24), Vector2(clock_w, 56))
	_panel(clock)
	_text(clock_text, clock.position + Vector2(0, 38), 30, TEXT, HORIZONTAL_ALIGNMENT_CENTER, 118, _heading)
	draw_line(clock.position + Vector2(118, 14), clock.position + Vector2(118, 42), PANEL_EDGE, 1.0)
	_caps(day_text, clock.position + Vector2(130, 35), 16, MUTED_COLOR, HORIZONTAL_ALIGNMENT_LEFT, clock_w - 140)
	if wave_text != "":
		var urgent := wave_text.begins_with("BÜYÜK") or wave_text.begins_with("BUYUK") or wave_text.contains("BU GECE")
		var color := RED if urgent else ACCENT
		var label := UiTheme.upper(wave_text)
		var tw := _label.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 28
		var rect := Rect2(Vector2(s.x * 0.5 - tw * 0.5, clock.end.y + 8), Vector2(tw, 28))
		# Acik gokyuzunde de okunsun: once opak koyu taban, ustune renk tonu.
		draw_style_box(_box("wave_base", PANEL, 14), rect)
		draw_style_box(_box("wave", Color(color.r, color.g, color.b, 0.12 if not urgent else 0.3), 14,
			Color(color.r, color.g, color.b, 0.6)), rect)
		draw_string(_label, rect.position + Vector2(0, 19), label, HORIZONTAL_ALIGNMENT_CENTER, tw, 15, color)
	if heading >= 0.0:
		_draw_compass(Vector2(s.x * 0.5, clock.end.y + (48 if wave_text != "" else 14)))
	if power_text != "":
		var pw := _font.get_string_size(power_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 32
		var prect := Rect2(Vector2(s.x - 32 - pw, 80), Vector2(pw, 32))
		_panel(prect, 6)
		_text(power_text, prect.position + Vector2(16, 22), 16, Color(0.95, 0.85, 0.45), HORIZONTAL_ALIGNMENT_LEFT, pw - 24)
	if region_text != "":
		var rw := minf(_font.get_string_size(region_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x + 36, 720.0)
		var rect := Rect2(Vector2(s.x - 32 - rw, 32), Vector2(rw, 40))
		_panel(rect)
		_text(region_text, rect.position + Vector2(18, 27), 18, Color(0.8, 0.86, 0.93), HORIZONTAL_ALIGNMENT_LEFT, rw - 36)

	# Orta: etkilesim ipucu ([E] tus kapagi olarak) ve ilerleme
	if prompt != "":
		_draw_prompt(Vector2(s.x * 0.5, s.y * 0.5 + 90))
	if progress >= 0.0:
		var bar := Rect2(Vector2(s.x * 0.5 - 170, s.y * 0.5 + 118), Vector2(340, 8))
		draw_style_box(_box("progress_bg", Color(0, 0, 0, 0.45), 6), bar.grow(4))
		_meter(bar, progress, ACCENT)
		_free_text(progress_label, bar.position + Vector2(0, 34), 18, ACCENT, HORIZONTAL_ALIGNMENT_CENTER, 340)

	# Sol ust (gorev kartinin altinda): mesaj akisi
	var y := 124.0 if objective != "" else 40.0
	for entry: Dictionary in _messages:
		var alpha := clampf(entry.time, 0.0, 1.0)
		var color: Color = entry.color
		var text: String = entry.text
		var tw := minf(_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x + 30, 1100.0)
		var rect := Rect2(Vector2(32, y), Vector2(tw, 34))
		draw_style_box(_box("msg", Color(PANEL.r, PANEL.g, PANEL.b, PANEL.a * 0.85 * alpha), 6), rect)
		draw_rect(Rect2(rect.position + Vector2(0, 7), Vector2(3, 20)), Color(color.r, color.g, color.b, alpha))
		_text(text, rect.position + Vector2(16, 23), 18, Color(color.r, color.g, color.b, alpha), HORIZONTAL_ALIGNMENT_LEFT, tw - 26)
		y += 40.0


func _draw_compass(top_center: Vector2) -> void:
	## Pusula seridi: 120 derecelik pencere, ana yonler harfli.
	var w := 360.0
	var rect := Rect2(Vector2(top_center.x - w * 0.5, top_center.y), Vector2(w, 26))
	_panel(rect, 6)
	var names := {0: "K", 45: "KD", 90: "D", 135: "GD", 180: "G", 225: "GB", 270: "B", 315: "KB"}
	for deg in range(0, 360, 15):
		var delta := wrapf(float(deg) - heading, -180.0, 180.0)
		if absf(delta) > 60.0:
			continue
		var x := top_center.x + delta / 60.0 * (w * 0.5 - 14.0)
		if names.has(deg):
			var label: String = names[deg]
			draw_string(_label, Vector2(x - 20, rect.position.y + 19), label, HORIZONTAL_ALIGNMENT_CENTER, 40, 14,
				ACCENT if deg == 0 else TEXT)
		else:
			draw_line(Vector2(x, rect.position.y + 8), Vector2(x, rect.end.y - 8), Color(1, 1, 1, 0.3), 1.0)
	draw_line(Vector2(top_center.x, rect.position.y + 2), Vector2(top_center.x, rect.position.y + 7), ACCENT, 2.0)


func _draw_prompt(center: Vector2) -> void:
	## "[E] Al -- Konserve" -> tus kapagi + metin, ortalanmis.
	var key := ""
	var rest := prompt
	if prompt.begins_with("["):
		var close := prompt.find("]")
		if close > 1 and close < 14:
			key = prompt.substr(1, close - 1)
			rest = prompt.substr(close + 1).strip_edges()
	rest = rest.replace(" -- ", "  ·  ")
	var size_px := 21
	var text_w := _font.get_string_size(rest, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
	var key_w := 0.0
	if key != "":
		key_w = maxf(_label.get_string_size(UiTheme.upper(key), HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x + 18.0, 27.0) + 12.0
	var total := minf(text_w + key_w, 1100.0)
	var box := Rect2(Vector2(center.x - total * 0.5 - 18, center.y - 28), Vector2(total + 36, 44))
	draw_style_box(_box("prompt", Color(0.02, 0.025, 0.03, 0.62), 8, PANEL_EDGE), box)
	var x := center.x - total * 0.5
	if key != "":
		x += _keycap(UiTheme.upper(key), Vector2(x, center.y), 18) + 12.0
	_text(rest, Vector2(x, center.y + 1), size_px, TEXT, HORIZONTAL_ALIGNMENT_LEFT, total - key_w + 4)
