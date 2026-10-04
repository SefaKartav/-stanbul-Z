class_name CraftingScreen
extends Screen
## Uretim (C). Solda kategori rayi, ortada ikonlu tarif listesi, sagda secili
## tarifin ayrinti karti ve eylem cubugu.
##
## KORUNAN KURALLAR: tag'li alternatif girdi, minimum kalite, tuketilmeyen
## takim, istasyon/kademe, sema kilidi, sure, yan urun, basarisizlik, koloni
## is emri. Uretim SURELIDIR; malzeme her adet TAMAMLANDIGINDA o anda yeniden
## denetlenerek tek islemde harcanir (bkz. Game._update_craft_job). Iptal,
## istasyondan/usten uzaklasma ya da kayit yukleme esya cogaltmaz ve
## karsiliksiz malzeme yakmaz.
##
## KULLANILABILIRLIK
##   * Arama Turkce karakterlere duyarsiz (c/ç, s/ş, g/ğ, i/ı, o/ö, u/ü).
##   * Liste secimi ve kaydirma yenilemede SIFIRLANMAZ.
##   * Her gereksinim ayri satir: eldeki/gereken, "nerede bulunur" (gercek
##     loot verisinden), uretilebiliyorsa "tarife git" (ve "geri").
##   * Adet: yazilabilir, +/-, "en fazla N" (kopya envanterde gercek harcama
##     sirasiyla hesaplanir: ayni yigin iki alternatif girdiye sayilmaz).
##   * "Harcanacak": secili kaynaktan hangi yiginlarin (kaliteleriyle)
##     kullanilacagi uretimden ONCE gorunur.
##   * Kaynak secimi (canta / ortak depo) erisilemezse SESSIZCE degismez;
##     neden yazilir ve uretim dugmesi kapanir.
##   * Ray: on uretim AILESI (belgenin tablosu); aramanin altinda ailenin alt
##     kategorileri. Kilitli tarifler kilit simgesiyle ve ACILMA YOLUYLA
##     gorunur ("Yalnizca ogrenilmis" ile gizlenir).
##   * Kuyruk: en fazla 8 is, her biri ayri iptal edilir (malzeme adet
##     bitiminde alindigi icin iptal esya yakmaz ya da cogaltmaz).
##   * ~760 tarif: arama yazarken yenileme 0,15 sn ertelenir; tarif ureten
##     dizini bir kez kurulur.

const ALL := "Tumu"
const SEARCH_DELAY := 0.15

var search_box: LineEdit
var category_rail: VBoxContainer
var sub_row: HFlowContainer
var only_craftable: CheckBox
var only_favorites: CheckBox
var only_known: CheckBox
var build_button: Button
var how_label: Label
var queue_box: VBoxContainer
var _queue_sig := ""
var _subcategory := ""
var _search_timer := -1.0
var _producers: Dictionary = {}     # esya -> [RecipeDef]
var recipe_list: ItemList
var list_count: Label
var station_row: HFlowContainer
var header: Label
var output_label: Label
var output_icon: TextureRect
var chips: HFlowContainer
var status_panel: PanelContainer
var status_label: Label
var requirements: VBoxContainer
var consumption: Label
var quantity_edit: SpinBox
var max_button: Button
var source_box: OptionButton
var source_note: Label
var craft_button: Button
var order_button: Button
var favorite_button: Button
var back_button: Button
var job_label: Label
var job_bar: ProgressBar
var job_cancel: Button
var description: Label
var _recipes: Array = []
var _selected: RecipeDef
var _history: Array = []          # alt tarife gidildiginde geri donus yigini
var _categories: Array = []
var _category := ALL
var _rail_buttons: Dictionary = {}  # kategori -> Button
var _rail_group := ButtonGroup.new()


func _init() -> void:
	super._init()
	title = "Üretim"
	subtitle = "Topla · İşle · Üret"
	toggle_action = "craft"


static func norm(text: String) -> String:
	## Turkce karakterlere duyarsiz arama anahtari.
	var t := text.to_lower()
	for pair: Array in [["ç", "c"], ["ş", "s"], ["ğ", "g"], ["ı", "i"], ["i̇", "i"], ["ö", "o"], ["ü", "u"],
			["Ç", "c"], ["Ş", "s"], ["Ğ", "g"], ["İ", "i"], ["Ö", "o"], ["Ü", "u"]]:
		t = t.replace(pair[0], pair[1])
	return t


static func category_name(category: String) -> String:
	if category == ALL:
		return "Tümü"
	return str(Content.ui_names.get("categories", {}).get(category, category.capitalize()))


const FAMILY_SHORT := {"build": "Yapı", "process": "İşleme", "tools": "Alet ve bakım", "weapons": "Silah ve mühimmat",
	"defense": "Savunma ve tuzak", "power": "Elektrik", "food": "Su, yemek, tarım", "health": "Sağlık",
	"storage": "Depo ve koloni", "vehicle": "Araç ve keşif"}


static func family_name(family: String) -> String:
	if family == ALL:
		return "Tümü"
	return str(RecipeDef.FAMILY_NAMES.get(family, family))


static func family_short(family: String) -> String:
	if family == ALL:
		return "Tümü"
	return str(FAMILY_SHORT.get(family, family_name(family)))


static func sub_of(recipe: RecipeDef) -> String:
	## Alt kategori: tarifte yazilmadiysa kategorinin Turkce adi.
	return recipe.subcategory if recipe.subcategory != "" else category_name(recipe.category)


func _known(recipe: RecipeDef) -> bool:
	return recipe.unlocked or game.crafting.known_recipes.has(recipe.id)


func _build_content() -> void:
	# --- Sol: kategori rayi -------------------------------------------------
	var rail_card := UiTheme.card("Inset")
	rail_card.custom_minimum_size.x = 230
	body.add_child(rail_card)
	var rail_scroll := ScrollContainer.new()
	rail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rail_card.add_child(rail_scroll)
	category_rail = VBoxContainer.new()
	category_rail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	category_rail.add_theme_constant_override("separation", 2)
	rail_scroll.add_child(category_rail)

	# --- Orta: arama, filtre, liste ---------------------------------------
	var middle := Screen.column(500, false)
	middle.add_theme_constant_override("separation", 10)
	body.add_child(middle)
	search_box = LineEdit.new()
	search_box.placeholder_text = "Ara: ürün ya da malzeme adı…"
	search_box.clear_button_enabled = true
	search_box.text_changed.connect(func(_t: String) -> void: _search_timer = SEARCH_DELAY)
	middle.add_child(search_box)
	sub_row = HFlowContainer.new()
	sub_row.add_theme_constant_override("h_separation", 6)
	sub_row.add_theme_constant_override("v_separation", 6)
	middle.add_child(sub_row)
	var toggles := HBoxContainer.new()
	toggles.add_theme_constant_override("separation", 14)
	middle.add_child(toggles)
	only_craftable = CheckBox.new()
	only_craftable.text = "Yalnızca yapılabilir"
	only_craftable.toggled.connect(func(_b: bool) -> void: refresh())
	toggles.add_child(only_craftable)
	only_favorites = CheckBox.new()
	only_favorites.text = "Favoriler"
	only_favorites.toggled.connect(func(_b: bool) -> void: refresh())
	toggles.add_child(only_favorites)
	only_known = CheckBox.new()
	only_known.text = "Öğrenilmiş"
	only_known.tooltip_text = "Kilitli (şema/beceri/seviye bekleyen) tarifleri gizle"
	only_known.toggled.connect(func(_b: bool) -> void: refresh())
	toggles.add_child(only_known)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toggles.add_child(spacer)
	list_count = UiTheme.label("", 16, UiTheme.MUTED)
	list_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	toggles.add_child(list_count)
	recipe_list = ItemList.new()
	recipe_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	recipe_list.fixed_icon_size = Vector2i(40, 40)
	recipe_list.icon_mode = ItemList.ICON_MODE_LEFT
	recipe_list.item_selected.connect(func(i: int) -> void:
		if i < _recipes.size():
			_select(_recipes[i], false))
	middle.add_child(recipe_list)
	station_row = HFlowContainer.new()
	station_row.add_theme_constant_override("h_separation", 6)
	station_row.add_theme_constant_override("v_separation", 6)
	middle.add_child(station_row)

	# --- Sag: ayrinti karti -----------------------------------------------
	var right := Screen.column(700)
	right.add_theme_constant_override("separation", 12)
	body.add_child(right)
	var detail_card := UiTheme.card()
	detail_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(detail_card)
	var detail := VBoxContainer.new()
	detail.add_theme_constant_override("separation", 12)
	detail_card.add_child(detail)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	detail.add_child(top)
	var icon_frame := UiTheme.card("Inset")
	icon_frame.custom_minimum_size = Vector2(112, 112)
	top.add_child(icon_frame)
	output_icon = TextureRect.new()
	output_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	output_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	output_icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	icon_frame.add_child(output_icon)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", 6)
	top.add_child(titles)
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 10)
	titles.add_child(title_row)
	back_button = UiTheme.button("‹ Geri", _go_back)
	back_button.tooltip_text = "Bir önceki tarife dön"
	title_row.add_child(back_button)
	header = UiTheme.heading("Bir tarif seç", 32, UiTheme.TEXT)
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.clip_text = true
	header.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_row.add_child(header)
	favorite_button = UiTheme.button("☆", _toggle_favorite)
	favorite_button.custom_minimum_size = Vector2(44, 40)
	favorite_button.tooltip_text = "Favorilere ekle / çıkar"
	title_row.add_child(favorite_button)
	output_label = UiTheme.label("", 18, UiTheme.TEXT_DIM)
	titles.add_child(output_label)
	chips = HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 6)
	chips.add_theme_constant_override("v_separation", 6)
	titles.add_child(chips)

	status_panel = PanelContainer.new()
	detail.add_child(status_panel)
	status_label = UiTheme.label("", 17)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_panel.add_child(status_label)

	detail.add_child(UiTheme.section("Gereksinimler"))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail.add_child(scroll)
	requirements = VBoxContainer.new()
	requirements.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	requirements.add_theme_constant_override("separation", 8)
	scroll.add_child(requirements)
	consumption = UiTheme.label("", 15, UiTheme.MUTED)
	consumption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(consumption)
	description = UiTheme.label("", 17, UiTheme.TEXT_DIM)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(description)
	how_label = UiTheme.label("", 15, UiTheme.INFO)
	how_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(how_label)

	# --- Eylem cubugu -----------------------------------------------------
	var action_card := UiTheme.card()
	right.add_child(action_card)
	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	action_card.add_child(actions)
	var amount_row := HBoxContainer.new()
	amount_row.add_theme_constant_override("separation", 8)
	actions.add_child(amount_row)
	var amount_label := UiTheme.eyebrow("Adet")
	amount_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	amount_row.add_child(amount_label)
	var minus := UiTheme.button("−", func() -> void: quantity_edit.value -= 1)
	minus.custom_minimum_size.x = 40
	amount_row.add_child(minus)
	quantity_edit = SpinBox.new()
	quantity_edit.min_value = 1
	quantity_edit.max_value = WorkOrders.MAX_QUANTITY
	quantity_edit.value = 1
	quantity_edit.custom_minimum_size.x = 96
	quantity_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	quantity_edit.value_changed.connect(func(_v: float) -> void: _show_detail())
	amount_row.add_child(quantity_edit)
	var plus := UiTheme.button("+", func() -> void: quantity_edit.value += 1)
	plus.custom_minimum_size.x = 40
	amount_row.add_child(plus)
	max_button = UiTheme.button("En fazla", func() -> void:
		var n := _max_count()
		quantity_edit.value = maxi(1, n)
		_show_detail())
	amount_row.add_child(max_button)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	amount_row.add_child(gap)
	var source_label := UiTheme.eyebrow("Kaynak")
	source_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	amount_row.add_child(source_label)
	source_box = OptionButton.new()
	source_box.add_item("Çanta")
	source_box.add_item("Ortak depo")
	source_box.item_selected.connect(func(_i: int) -> void: refresh())
	amount_row.add_child(source_box)
	source_note = UiTheme.label("", 15, UiTheme.MUTED)
	source_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	actions.add_child(source_note)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	actions.add_child(buttons)
	order_button = UiTheme.button("Zanaatkâra iş emri ver", _order)
	buttons.add_child(order_button)
	build_button = UiTheme.button("İnşa kipinde kur (B)", func() -> void:
		if _selected != null and game.inventory.count(_selected.output_id) > 0:
			game.build.select_item(_selected.output_id)
			close())
	build_button.tooltip_text = "Çantadaki bu yapıyı/parçayı B kipinde seçili açar"
	buttons.add_child(build_button)
	var push := Control.new()
	push.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(push)
	craft_button = UiTheme.primary_button("Üret", _craft)
	craft_button.custom_minimum_size = Vector2(260, 48)
	buttons.add_child(craft_button)

	var job_row := HBoxContainer.new()
	job_row.add_theme_constant_override("separation", 10)
	actions.add_child(job_row)
	job_label = UiTheme.label("", 16, UiTheme.TEXT_DIM)
	job_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	job_label.clip_text = true
	job_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	job_row.add_child(job_label)
	job_bar = ProgressBar.new()
	job_bar.custom_minimum_size = Vector2(240, 12)
	job_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	job_bar.max_value = 1.0
	job_bar.show_percentage = false
	job_row.add_child(job_bar)
	job_cancel = UiTheme.button("İptal", func() -> void:
		game.cancel_craft()
		refresh())
	job_row.add_child(job_cancel)
	queue_box = VBoxContainer.new()
	queue_box.add_theme_constant_override("separation", 4)
	actions.add_child(queue_box)
	footer.text = "Üretim dünya akarken sürer (kuyruk en fazla %d iş). Malzeme her adet bittiğinde, o anda yeniden denetlenerek harcanır; iptal eşya yakmaz." % Game.CRAFT_QUEUE_MAX

	_categories = [ALL]
	for family: String in RecipeDef.FAMILIES:
		_categories.append(family)
	for recipe: RecipeDef in Content.recipes.values():
		var list: Array = _producers.get(recipe.output_id, [])
		list.append(recipe)
		_producers[recipe.output_id] = list
	_build_rail()


func _build_rail() -> void:
	category_rail.add_child(UiTheme.eyebrow("Aileler"))
	var counts := {ALL: Content.recipes.size()}
	for recipe: RecipeDef in Content.recipes.values():
		counts[recipe.family] = int(counts.get(recipe.family, 0)) + 1
	for category: String in _categories:
		var b := Button.new()
		b.theme_type_variation = "RailButton"
		b.toggle_mode = true
		b.button_group = _rail_group
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size.y = 38
		b.tooltip_text = family_name(category)
		# Ad solda, sayi sagda: dugme metni yerine icerde iki etiket.
		var row := HBoxContainer.new()
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		row.offset_left = 14
		row.offset_right = -12
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(row)
		var name := UiTheme.label(family_short(category), 18, UiTheme.TEXT_DIM)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		name.clip_text = true
		name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(name)
		var count := UiTheme.label(str(int(counts.get(category, 0))), 15, UiTheme.MUTED)
		count.add_theme_font_override("font", UiTheme.font_strong())
		count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		count.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(count)
		b.set_meta("name_label", name)
		b.button_pressed = category == _category
		b.pressed.connect(func() -> void:
			_category = category
			_subcategory = ""
			refresh())
		category_rail.add_child(b)
		_rail_buttons[category] = b


func _set_category(category: String) -> void:
	_category = category
	_subcategory = ""
	if _rail_buttons.has(category):
		(_rail_buttons[category] as Button).button_pressed = true


func _process(delta: float) -> void:
	if _search_timer >= 0.0:
		_search_timer -= delta
		if _search_timer < 0.0:
			refresh()
	_update_job()


func _build_sub_row() -> void:
	## Secili ailenin alt kategorileri (sayilariyla). "Tumu" ailesinde gizli.
	for child in sub_row.get_children():
		child.queue_free()
	sub_row.visible = _category != ALL
	if _category == ALL:
		return
	var counts := {}
	var order: Array = []
	for recipe: RecipeDef in Content.recipes.values():
		if recipe.family != _category:
			continue
		var sub := sub_of(recipe)
		if not counts.has(sub):
			order.append(sub)
		counts[sub] = int(counts.get(sub, 0)) + 1
	order.sort()
	order.push_front("")
	for sub: String in order:
		var b := Button.new()
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.button_pressed = sub == _subcategory
		b.text = ("Hepsi" if sub == "" else sub) + "  %d" % (int(counts.get(sub, 0)) if sub != "" else
			counts.values().reduce(func(a: int, n: int) -> int: return a + n, 0))
		b.add_theme_font_size_override("font_size", 15)
		if sub == _subcategory:
			b.add_theme_color_override("font_color", UiTheme.ACCENT)
			b.add_theme_color_override("font_pressed_color", UiTheme.ACCENT)
		b.pressed.connect(func() -> void:
			_subcategory = sub
			refresh())
		sub_row.add_child(b)


# ---------------------------------------------------------------------------
# Kaynak ve istasyon
# ---------------------------------------------------------------------------
func _stations() -> Dictionary:
	var available: Dictionary = game.placeables.best_station(game.player.global_position).available
	return available


func _base() -> Settlement:
	## Icinde bulunulan us; 'Ortak depo kurallari' becerisiyle 80 m cevresi de sayilir.
	if game.bases == null:
		return null
	return game.depot_base()


func _source() -> Inventory:
	## Secili kaynak; ERISILEMEZSE null (sessizce cantaya gecilmez).
	if source_box.selected == 1:
		var base := _base()
		return base.stockpile if base != null else null
	return game.inventory


func _station_for(recipe: RecipeDef) -> Array:
	## [istasyon, kademe] ya da [] (yakinda yok).
	if recipe.station == "hands":
		return ["hands", 1]
	var stations := _stations()
	if not stations.has(recipe.station):
		return []
	return [recipe.station, int(stations[recipe.station])]


func _check(recipe: RecipeDef) -> Dictionary:
	var source := _source()
	if source == null:
		return {"ok": false, "reason": "Ortak depoya erişim yok: kapalı bir üssün içinde olmalısın", "missing": [], "predicted_quality": 0.0}
	var st := _station_for(recipe)
	if st.is_empty():
		return {"ok": false, "reason": "'%s' gerekli, yakınında yok" % RecipeDef.STATION_NAMES.get(recipe.station, recipe.station),
			"missing": [], "predicted_quality": 0.0}
	return game.crafting.check(source, recipe, st[0], st[1], game.skills.bonus("craft_quality") * 100.0)


func _max_count() -> int:
	var source := _source()
	var st := _station_for(_selected) if _selected != null else []
	if _selected == null or source == null or st.is_empty():
		return 0
	return game.crafting.max_craftable(source, _selected, st[0], st[1], WorkOrders.MAX_QUANTITY)


static func _recipe_icon(recipe: RecipeDef) -> Texture2D:
	var output := Content.item(recipe.output_id)
	if output == null:
		return null
	return AssetLibrary.icon(AssetLibrary.item_model_id(output))


# ---------------------------------------------------------------------------
# Liste
# ---------------------------------------------------------------------------
func refresh() -> void:
	for category: String in _rail_buttons:
		var name_label: Label = (_rail_buttons[category] as Button).get_meta("name_label")
		name_label.add_theme_color_override("font_color", UiTheme.ACCENT if category == _category else UiTheme.TEXT_DIM)
	var stations := _stations()
	for child in station_row.get_children():
		child.queue_free()
	var near := UiTheme.eyebrow("Yakında")
	near.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	station_row.add_child(near)
	station_row.add_child(UiTheme.chip("El ile", UiTheme.TEXT_DIM))
	for station: String in stations:
		station_row.add_child(UiTheme.chip("%s T%d" % [RecipeDef.STATION_NAMES.get(station, station), stations[station]], UiTheme.ACCENT))
	var base := _base()
	source_note.text = "" if base != null else "Ortak depo yalnızca kapalı bir üssün içindeyken kullanılır."
	if source_box.selected == 1 and base == null:
		source_note.text = "SEÇİLİ KAYNAĞA ERİŞİLEMİYOR: ortak depo için üssün içine gir ya da kaynağı Çanta yap."
	source_note.add_theme_color_override("font_color", UiTheme.BAD if source_box.selected == 1 and base == null else UiTheme.MUTED)
	_search_timer = -1.0
	_build_sub_row()
	var query := norm(search_box.text.strip_edges())
	var entries: Array = []
	for recipe: RecipeDef in Content.recipes.values():
		if _category != ALL and recipe.family != _category:
			continue
		if _subcategory != "" and sub_of(recipe) != _subcategory:
			continue
		if only_favorites.button_pressed and not Settings.favorites.has(recipe.id):
			continue
		var known := _known(recipe)
		if only_known.button_pressed and not known:
			continue
		if query != "" and not _matches(recipe, query):
			continue
		# Kilitli tarif icin pahali denetim yapilmaz: zaten yapilamaz.
		var ok: bool = known and bool(_check(recipe).ok)
		if only_craftable.button_pressed and not ok:
			continue
		entries.append([recipe, ok, known])
	entries.sort_custom(func(a: Array, b: Array) -> bool:
		if a[1] != b[1]:
			return a[1]
		if a[2] != b[2]:
			return a[2]
		var fa: bool = Settings.favorites.has(a[0].id)
		var fb: bool = Settings.favorites.has(b[0].id)
		if fa != fb:
			return fa
		return a[0].name < b[0].name)
	# Kaydirma ve secim yenilemede korunur.
	var scroll := recipe_list.get_v_scroll_bar().value
	_recipes = entries.map(func(e: Array) -> RecipeDef: return e[0])
	recipe_list.clear()
	var craftable := 0
	for e: Array in entries:
		var recipe: RecipeDef = e[0]
		var star := "★  " if Settings.favorites.has(recipe.id) else ""
		var lock := "" if e[2] else "   · kilitli"
		var index := recipe_list.add_item("%s%s%s" % [star, recipe.name, lock], _recipe_icon(recipe))
		recipe_list.set_item_custom_fg_color(index, UiTheme.TEXT if e[1] else (UiTheme.MUTED if e[2] else UiTheme.MUTED.darkened(0.25)))
		recipe_list.set_item_tooltip(index, "%s · %s" % [sub_of(recipe),
			"yapılabilir" if e[1] else ("şu an yapılamaz" if e[2] else recipe.learn_text())])
		if e[1]:
			craftable += 1
	list_count.text = "%d tarif · %d yapılabilir" % [entries.size(), craftable]
	# Acilista ayrinti bos kalmasin: secim yoksa listenin ilki.
	if _selected == null and not _recipes.is_empty():
		_selected = _recipes[0]
	var at := _recipes.find(_selected)
	if at >= 0:
		recipe_list.select(at)
	recipe_list.get_v_scroll_bar().value = scroll
	_show_detail()


func _matches(recipe: RecipeDef, query: String) -> bool:
	if norm(recipe.name).contains(query) or recipe.output_id.contains(query):
		return true
	var output := Content.item(recipe.output_id)
	if output != null and norm(output.name).contains(query):
		return true
	for ingredient: Dictionary in recipe.inputs:
		if ingredient.item != "":
			var def := Content.item(ingredient.item)
			if def != null and norm(def.name).contains(query):
				return true
		elif norm(str(Content.ui_names.get("tags", {}).get(ingredient.tag, ""))).contains(query):
			return true
	return false


func _select(recipe: RecipeDef, remember: bool) -> void:
	if remember and _selected != null and _selected != recipe:
		_history.append(_selected)
	_selected = recipe
	var at := _recipes.find(recipe)
	if at >= 0:
		recipe_list.select(at)
		recipe_list.ensure_current_is_visible()
	_show_detail()


func _go_back() -> void:
	if not _history.is_empty():
		_selected = _history.pop_back()
		refresh()


# ---------------------------------------------------------------------------
# Ayrinti
# ---------------------------------------------------------------------------
func _producer_of(item_id: String) -> RecipeDef:
	## Bilinen ilk ureten tarif; yoksa kilitli olani (acilma yolu gorunsun).
	var fallback: RecipeDef = null
	for recipe: RecipeDef in _producers.get(item_id, []):
		if _known(recipe):
			return recipe
		if fallback == null:
			fallback = recipe
	return fallback


func _set_status(text: String, color: Color) -> void:
	status_panel.visible = text != ""
	status_label.text = text
	status_label.add_theme_color_override("font_color", color.lightened(0.15))
	status_panel.add_theme_stylebox_override("panel", UiTheme.box(Color(color.r, color.g, color.b, 0.1), 5,
		Color(color.r, color.g, color.b, 0.4), 1, 14, 8))


func _show_detail() -> void:
	back_button.disabled = _history.is_empty()
	for child in requirements.get_children():
		child.queue_free()
	for child in chips.get_children():
		child.queue_free()
	_update_job()
	if _selected == null:
		header.text = UiTheme.upper("Bir tarif seç")
		output_label.text = "Soldaki listeden bir tarif seç; gereksinimler ve kaynak rehberi burada görünür."
		output_icon.texture = null
		_set_status("", UiTheme.MUTED)
		consumption.text = ""
		description.text = ""
		craft_button.disabled = true
		order_button.disabled = true
		favorite_button.disabled = true
		build_button.visible = false
		how_label.text = ""
		max_button.text = "En fazla"
		return
	favorite_button.disabled = false
	var recipe := _selected
	var check := _check(recipe)
	var source := _source()
	var quantity := int(quantity_edit.value)
	var output := Content.item(recipe.output_id)
	header.text = UiTheme.upper(recipe.name)
	output_label.text = "Çıktı: %d × %s" % [recipe.output_count, output.name if output != null else recipe.output_id]
	output_icon.texture = _recipe_icon(recipe)
	favorite_button.text = "★" if Settings.favorites.has(recipe.id) else "☆"

	chips.add_child(UiTheme.chip("%s · %s" % [family_name(recipe.family), sub_of(recipe)], UiTheme.TEXT_DIM))
	chips.add_child(UiTheme.chip("%s%s" % [RecipeDef.STATION_NAMES.get(recipe.station, recipe.station),
		(" T%d" % recipe.station_tier) if recipe.station != "hands" else ""], UiTheme.ACCENT))
	chips.add_child(UiTheme.chip("%.0f sn / adet" % recipe.time, UiTheme.INFO))
	if recipe.power > 0.0:
		chips.add_child(UiTheme.chip("Elektrik %d W" % int(recipe.power), UiTheme.INFO))
	if output != null:
		chips.add_child(UiTheme.chip(str(ItemUse.CLASS_NAMES.get(ItemUse.classify(output), "")), UiTheme.GOOD))
	if not _known(recipe):
		chips.add_child(UiTheme.chip("Kilitli", UiTheme.BAD))
	if recipe.failure_chance > 0:
		chips.add_child(UiTheme.chip("Başarısızlık %%%d" % int(recipe.failure_chance * 100), UiTheme.BAD))
	if not recipe.byproducts.is_empty():
		var by := PackedStringArray()
		for entry: Array in recipe.byproducts:
			by.append("%d× %s" % [entry[1], Content.item(entry[0]).name])
		chips.add_child(UiTheme.chip("Yan ürün: " + ", ".join(by), UiTheme.GOOD))

	if check.ok:
		_set_status("Yapılabilir · tahmini kalite %d (%s)" % [int(check.predicted_quality),
			ItemDef.quality_name(check.predicted_quality)], UiTheme.GOOD)
	elif not _known(recipe):
		_set_status("Kilitli · nasıl açılır: " + recipe.learn_text(), UiTheme.BAD)
	else:
		_set_status("Yapılamaz · " + str(check.reason), UiTheme.BAD)

	for ingredient: Dictionary in recipe.inputs:
		requirements.add_child(_requirement_row(ingredient, source, quantity))

	# Harcanacak yiginlar (1 adet icin) -- degerli malzeme habersiz gitmesin.
	if source != null and check.ok:
		var used := PackedStringArray()
		for part: Dictionary in game.crafting.consumption_plan(source, recipe):
			for stack: ItemStack in part.stacks:
				used.append("%s ×%d (kalite %d)" % [stack.definition.name, stack.quantity, int(stack.quality)])
		consumption.text = "Harcanacak (1 adet): " + ", ".join(used)
	else:
		consumption.text = ""
	var n := _max_count()
	max_button.text = "En fazla %d" % n
	var full: bool = game.craft_queue.size() >= Game.CRAFT_QUEUE_MAX
	var queued: bool = not game.craft_queue.is_empty()
	craft_button.disabled = not check.ok or full or n < 1
	var verb := "SIRAYA EKLE" if queued else "ÜRET"
	craft_button.text = ("%s  ×%d" % [verb, quantity]) if n >= quantity else ("%s  ×%d  (en fazla %d)" % [verb, quantity, n])
	craft_button.tooltip_text = ("Kuyruk dolu (en fazla %d iş)" % Game.CRAFT_QUEUE_MAX) if full else str(check.get("reason", ""))
	var base := _base()
	order_button.disabled = base == null
	order_button.tooltip_text = "" if base != null else "İş emri için bir üssün içinde olmalısın"
	description.text = recipe.description
	how_label.text = ("Kullanım: " + ItemUse.how_to(output)) if output != null else ""
	var placeable: bool = output != null and ItemUse.classify(output) in ["place", "build"]
	build_button.visible = placeable
	build_button.disabled = not placeable or game.inventory.count(recipe.output_id) <= 0
	if placeable and build_button.disabled:
		build_button.tooltip_text = "Önce üret: çantada yok"
	else:
		build_button.tooltip_text = "Çantadaki bu yapıyı/parçayı B kipinde seçili açar"


func _requirement_row(ingredient: Dictionary, source: Inventory, quantity: int) -> Control:
	var have: int = game.crafting.available(source, ingredient) if source != null else 0
	var need: int = ingredient.count * (quantity if ingredient.consumed else 1)
	var ok := have >= need
	var tone := UiTheme.GOOD if ok else UiTheme.BAD

	var card := PanelContainer.new()
	var style := UiTheme.box(UiTheme.INSET, 5, UiTheme.LINE_SOFT, 1, 12, 10)
	style.border_color = Color(tone.r, tone.g, tone.b, 0.55)
	style.border_width_left = 3
	card.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(44, 44)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if ingredient.item != "":
		var def := Content.item(ingredient.item)
		if def != null:
			icon.texture = AssetLibrary.icon(AssetLibrary.item_model_id(def))
	else:
		var matches: Array = Content.graph.items_with_tag(ingredient.tag)
		if not matches.is_empty():
			icon.texture = AssetLibrary.icon(AssetLibrary.item_model_id(Content.item(matches[0])))
	row.add_child(icon)

	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.add_theme_constant_override("separation", 2)
	row.add_child(texts)
	var name := UiTheme.label(RecipeDef.describe_ingredient(ingredient, Content.items), 18, UiTheme.TEXT)
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	texts.add_child(name)
	if ingredient.item != "":
		var where := LootSources.describe(ingredient.item)
		if where != "":
			texts.add_child(_hint_line("Bulunur: " + where))
	else:
		var options: Array = Content.graph.items_with_tag(ingredient.tag).map(func(id: String) -> String: return Content.item(id).name)
		options.sort()
		texts.add_child(_hint_line("Karşılayan: " + ", ".join(options.slice(0, 6)) + ("…" if options.size() > 6 else "")))
		var where := LootSources.describe_tag(ingredient.tag)
		if where != "":
			texts.add_child(_hint_line("Bulunur: " + where))

	var counts := VBoxContainer.new()
	counts.custom_minimum_size.x = 150
	counts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	counts.add_theme_constant_override("separation", 4)
	row.add_child(counts)
	var amount := UiTheme.label("%d / %d" % [have, need], 22, tone)
	amount.add_theme_font_override("font", UiTheme.font_strong())
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	counts.add_child(amount)
	var meter := ProgressBar.new()
	meter.show_percentage = false
	meter.custom_minimum_size = Vector2(150, 6)
	meter.max_value = 1.0
	meter.value = clampf(float(have) / maxf(1.0, need), 0.0, 1.0)
	meter.add_theme_stylebox_override("fill", UiTheme.box(tone, 3))
	meter.add_theme_stylebox_override("background", UiTheme.box(Color(1, 1, 1, 0.06), 3))
	counts.add_child(meter)
	var state := UiTheme.label("TAMAM" if ok else "EKSİK %d" % (need - have), 14, tone)
	state.add_theme_font_override("font", UiTheme.font_label())
	state.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if not ingredient.consumed:
		state.text += " · TAKIM (harcanmaz)"
	counts.add_child(state)

	if ingredient.item != "":
		var producer := _producer_of(ingredient.item)
		if producer != null and producer != _selected:
			var go := UiTheme.button("Tarife git ›", func() -> void:
				search_box.text = ""
				_set_category(ALL)
				refresh()
				_select(producer, true))
			go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(go)
	return card


static func _hint_line(text: String) -> Label:
	var l := UiTheme.label(text, 15, UiTheme.MUTED)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _update_job() -> void:
	if job_label == null:
		return
	var job: Dictionary = game.craft_job
	var active := not job.is_empty()
	job_bar.visible = active
	job_cancel.visible = active
	_update_queue()
	if not active:
		var done: int = game.craft_done_last
		job_label.text = ("Son üretim tamamlandı: %d adet" % done) if done > 0 else "Süren üretim yok."
		job_label.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
		return
	var recipe: RecipeDef = job.recipe
	job_bar.value = clampf(float(job.elapsed) / maxf(0.1, recipe.time), 0.0, 1.0)
	var paused := str(job.get("paused", ""))
	if paused != "":
		job_label.text = "DURAKLADI: %s · %s" % [recipe.name, paused]
		job_label.add_theme_color_override("font_color", UiTheme.BAD)
	else:
		job_label.text = "Üretiliyor: %s · %d kaldı, %d tamamlandı" % [recipe.name, int(job.remaining), int(job.get("done", 0))]
		job_label.add_theme_color_override("font_color", UiTheme.TEXT_DIM)


func _update_queue() -> void:
	## Bekleyen isler (ilki calisan is; yukarida). Liste yalniz kuyruk
	## degisince yeniden kurulur.
	var sig := ""
	for job: Dictionary in game.craft_queue:
		sig += "%s:%d;" % [(job.recipe as RecipeDef).id, int(job.remaining)]
	if sig == _queue_sig:
		return
	_queue_sig = sig
	for child in queue_box.get_children():
		child.queue_free()
	if game.craft_queue.size() <= 1:
		return
	queue_box.add_child(UiTheme.eyebrow("Sırada (%d/%d)" % [game.craft_queue.size() - 1, Game.CRAFT_QUEUE_MAX - 1]))
	for i in range(1, game.craft_queue.size()):
		var job: Dictionary = game.craft_queue[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var l := UiTheme.label("%d.  %s ×%d" % [i, (job.recipe as RecipeDef).name, int(job.remaining)], 15, UiTheme.TEXT_DIM)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.clip_text = true
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(l)
		var index := i
		var x := UiTheme.button("✕", func() -> void:
			game.dequeue_craft(index)
			refresh())
		x.tooltip_text = "Kuyruktan çıkar (malzeme harcanmamıştı)"
		x.custom_minimum_size = Vector2(36, 30)
		row.add_child(x)
		queue_box.add_child(row)


# ---------------------------------------------------------------------------
# Eylemler
# ---------------------------------------------------------------------------
func _craft() -> void:
	if _selected == null:
		return
	var source := _source()
	var st := _station_for(_selected)
	if source == null or st.is_empty():
		return
	game.start_craft(_selected, mini(int(quantity_edit.value), maxi(1, _max_count())), source, st[0], st[1])
	refresh()


func _order() -> void:
	var base := _base()
	if base == null or _selected == null:
		return
	var result: String = game.bases.colony.work_orders.add(_selected.id, int(quantity_edit.value), base.id)
	var text: String = {"workorder.added": "İş emri verildi", "workorder.increased": "İş emri artırıldı",
		"workorder.queue_full": "Kuyruk dolu (en fazla 8 emir)"}.get(result, result)
	game.hud.message("%s: %d× %s" % [text, int(quantity_edit.value), _selected.name], Hud.ACCENT)


func _toggle_favorite() -> void:
	if _selected == null:
		return
	if Settings.favorites.has(_selected.id):
		Settings.favorites.erase(_selected.id)
	else:
		Settings.favorites.append(_selected.id)
	Settings.save_settings()
	refresh()
