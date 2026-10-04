class_name PauseScreen
extends Screen
## Esc menusu: devam, kaydet, yukle, ayarlar (hassasiyet, FOV, bas
## sallanmasi, sarsinti, gorus, golge, ses, tam ekran, TUS ATAMALARI),
## ana menu, cikis. Dunyayi DURDURUR.

var content: VBoxContainer
var _waiting_action := ""
var _binding_buttons: Dictionary = {}
var _tab_group := ButtonGroup.new()


func _init() -> void:
	super._init()
	title = "Duraklatıldı"
	subtitle = "Dünya durdu"
	pauses_world = true


func _build_content() -> void:
	var menu := Screen.column(300, false)
	menu.add_theme_constant_override("separation", 4)
	body.add_child(menu)
	menu.add_child(_menu_button("Devam et", close))
	menu.add_child(_menu_button("Kaydet  (F5)", func() -> void:
		game.save_game(SaveSystem.QUICKSAVE)))
	menu.add_child(_menu_button("Son kaydı yükle  (F9)", func() -> void:
		game.request_load(SaveSystem.QUICKSAVE)))
	var sep := HSeparator.new()
	menu.add_child(sep)
	var settings_tab := _tab_button("Ayarlar", _show_settings)
	settings_tab.button_pressed = true
	menu.add_child(settings_tab)
	menu.add_child(_tab_button("Tuş atamaları", _show_bindings))
	var push := Control.new()
	push.size_flags_vertical = Control.SIZE_EXPAND_FILL
	menu.add_child(push)
	menu.add_child(_menu_button("Ana menü", func() -> void: game.to_main_menu()))
	var quit := _menu_button("Oyundan çık", func() -> void: game.get_tree().quit())
	quit.add_theme_color_override("font_hover_color", UiTheme.BAD)
	menu.add_child(quit)

	body.add_child(VSeparator.new())
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_left", 12)
	pad.add_theme_constant_override("margin_right", 24)
	scroll.add_child(pad)
	content = Screen.column(700)
	content.add_theme_constant_override("separation", 10)
	pad.add_child(content)
	footer.text = "Ayarlar anında uygulanır ve kaydedilir."
	_show_settings()


func _menu_button(text: String, callback: Callable) -> Button:
	var b := UiTheme.menu_item(text, callback)
	b.add_theme_font_size_override("font_size", 22)
	return b


func _tab_button(text: String, callback: Callable) -> Button:
	var b := _menu_button(text, callback)
	b.toggle_mode = true
	b.button_group = _tab_group
	return b


func _clear() -> void:
	for child in content.get_children():
		child.queue_free()
	_binding_buttons.clear()


func _row(label: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var name := UiTheme.label(label, 19, UiTheme.TEXT_DIM)
	name.custom_minimum_size.x = 300
	name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(name)
	content.add_child(row)
	return row


func _slider(label: String, value: float, lo: float, hi: float, step: float, apply: Callable) -> void:
	var row := _row(label)
	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = step
	slider.value = value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fmt := "%d" if step >= 1.0 else "%.2f"
	var shown := UiTheme.label(fmt % value, 19, UiTheme.ACCENT)
	shown.add_theme_font_override("font", UiTheme.font_strong())
	shown.custom_minimum_size.x = 70
	shown.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	slider.value_changed.connect(func(v: float) -> void:
		shown.text = fmt % v
		apply.call(v)
		Settings.save_settings())
	row.add_child(slider)
	row.add_child(shown)


func _choice(label: String, names: Array, selected: int, apply: Callable) -> void:
	## Dugme grubu: secenekler yan yana, secili olan vurgulu.
	var row := _row(label)
	var group := ButtonGroup.new()
	for i in names.size():
		var b := UiTheme.button(str(names[i]), func() -> void:
			apply.call(i)
			Settings.save_settings())
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = i == selected
		b.custom_minimum_size.x = 110
		row.add_child(b)


func _mark_custom() -> void:
	## Elle degisiklik: on ayar "Ozel" olur (ayar kaydi slider/secim sonrasi yapilir).
	Settings.graphics_preset = 3


func _toggle(label: String, value: bool, apply: Callable) -> void:
	var box := CheckBox.new()
	box.text = label
	box.button_pressed = value
	box.toggled.connect(func(on: bool) -> void:
		apply.call(on)
		Settings.save_settings())
	content.add_child(box)


func _show_settings() -> void:
	_clear()
	content.add_child(UiTheme.section("Kontrol"))
	_slider("Yatay hassasiyet", Settings.sensitivity_x, 0.02, 0.5, 0.01, func(v: float) -> void: Settings.sensitivity_x = v)
	_slider("Dikey hassasiyet", Settings.sensitivity_y, 0.02, 0.5, 0.01, func(v: float) -> void: Settings.sensitivity_y = v)
	_toggle("Dikey ekseni ters çevir", Settings.invert_y, func(on: bool) -> void: Settings.invert_y = on)
	_toggle("Her zaman koş (3.6 m/sn; Caps Lock yürüyüş 1.7 m/sn, Shift depar 5.6 m/sn)", Settings.always_run,
		func(on: bool) -> void: Settings.always_run = on)
	content.add_child(UiTheme.section("Hayatta kalma"))
	var row := _row("Zorluk (açlık/susuzluk hızı ve hasarı)")
	var group := ButtonGroup.new()
	for level: String in ["kolay", "normal", "zor"]:
		var b := UiTheme.button(level.capitalize(), func() -> void:
			Settings.difficulty = level
			Settings.save_settings())
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = Settings.difficulty == level
		b.custom_minimum_size.x = 110
		row.add_child(b)
	content.add_child(UiTheme.section("Görüntü"))
	_slider("Görüş açısı (FOV)", Settings.fov, 60, 110, 1, func(v: float) -> void: Settings.fov = v)
	_slider("Baş sallanması", Settings.head_bob, 0, 1, 0.05, func(v: float) -> void: Settings.head_bob = v)
	_slider("Ekran sarsıntısı", Settings.screen_shake, 0, 1, 0.05, func(v: float) -> void: Settings.screen_shake = v)
	content.add_child(UiTheme.section("Grafik"))
	_choice("Kalite ön ayarı", Settings.PRESET_NAMES, Settings.graphics_preset, func(i: int) -> void:
		if i < 3:
			Settings.apply_preset(i)
			game.terrain.set_view_radius(Settings.view_distance)
			_show_settings())
	_choice("Kenar yumuşatma", Settings.AA_NAMES, Settings.aa_mode, func(i: int) -> void:
		Settings.aa_mode = i
		_mark_custom())
	_slider("Görüş mesafesi (chunk)", Settings.view_distance, 3, 14, 1, func(v: float) -> void:
		Settings.view_distance = int(v)
		game.terrain.set_view_radius(int(v))
		_mark_custom())
	_slider("Gölge kalitesi (0-3)", Settings.shadow_quality, 0, 3, 1, func(v: float) -> void:
		Settings.shadow_quality = int(v)
		_mark_custom())
	_toggle("Yumuşak görünüm (mat renkler, uzakta yumuşak doku)", Settings.soft_look, func(on: bool) -> void:
		Settings.soft_look = on)
	_toggle("Tam ekran", Settings.fullscreen, func(on: bool) -> void:
		Settings.fullscreen = on
		Settings.apply_display())
	content.add_child(UiTheme.section("Ses"))
	_slider("Ana ses", Settings.master_volume, 0, 1, 0.05, func(v: float) -> void:
		Settings.master_volume = v
		Settings.apply_display())


func _show_bindings() -> void:
	_clear()
	content.add_child(UiTheme.section("Tuş atamaları"))
	content.add_child(UiTheme.label("Değiştirmek için düğmeye bas, sonra yeni tuşa ya da fare düğmesine bas. Esc vazgeçer.", 17, UiTheme.MUTED))
	for action: String in Settings.ACTIONS:
		var row := _row(Settings.ACTIONS[action][0])
		var button := UiTheme.button(Settings.binding_label(action), _begin_rebind.bind(action))
		button.custom_minimum_size.x = 220
		row.add_child(button)
		_binding_buttons[action] = button
	var reset := UiTheme.button("Varsayılanlara dön", func() -> void:
		Settings.reset_bindings()
		_show_bindings())
	reset.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	content.add_child(reset)


func _begin_rebind(action: String) -> void:
	_waiting_action = action
	(_binding_buttons[action] as Button).text = "… bir tuşa bas"


func _input(event: InputEvent) -> void:
	if _waiting_action == "" or not visible:
		return
	if (event is InputEventKey and event.pressed and not event.echo) or (event is InputEventMouseButton and event.pressed):
		if event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
			_waiting_action = ""
			_show_bindings()
		else:
			Settings.rebind(_waiting_action, event)
			_waiting_action = ""
			_show_bindings()
		get_viewport().set_input_as_handled()
