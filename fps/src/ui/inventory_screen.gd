class_name InventoryScreen
extends Screen
## Envanter (I / Tab): canta, ortak depo, esya ayrintisi, kullan/birak,
## silah yuvasina ata, depoya aktar.
##
## CANTA - ORTAK DEPO AYRIMI: depo yalnizca kapali bir ussun icindeyken
## acilir. Mal tasimak bir EYLEMDIR; aksi halde depo sadece daha buyuk bir
## canta olurdu (eski oyunun kurali).

var bag_list: ItemList
var stock_list: ItemList
var stats: HBoxContainer
var detail: Label
var detail_title: Label
var detail_icon: TextureRect
var detail_chips: HFlowContainer
var actions: HFlowContainer
var stock_title: Label
var stock_note: Label
var _bag_stacks: Array = []
var _stock_stacks: Array = []
var _selected: ItemStack
var _selected_from := "bag"


func _init() -> void:
	super._init()
	title = "Envanter"
	subtitle = "Çanta · Depo · Bagaj"
	toggle_action = "inventory"


func _build_content() -> void:
	# Govdeyi dikey kurmak icin ust istatistik seridi govdenin USTUNE eklenir.
	stats = HBoxContainer.new()
	stats.add_theme_constant_override("separation", 12)
	root.add_child(stats)
	root.move_child(stats, body.get_index())

	var left := Screen.column(520)
	body.add_child(left)
	left.add_child(UiTheme.section("Çanta"))
	bag_list = ItemList.new()
	bag_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bag_list.fixed_icon_size = Vector2i(36, 36)
	bag_list.item_selected.connect(func(i: int) -> void: _select(_bag_stacks[i], "bag"))
	left.add_child(bag_list)

	var middle := Screen.column(460)
	body.add_child(middle)
	middle.add_child(UiTheme.section("Ayrıntı"))
	var card := UiTheme.card()
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.add_child(card)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 12)
	card.add_child(inner)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 14)
	inner.add_child(top)
	var frame := UiTheme.card("Inset")
	frame.custom_minimum_size = Vector2(96, 96)
	top.add_child(frame)
	detail_icon = TextureRect.new()
	detail_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	detail_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	frame.add_child(detail_icon)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", 6)
	top.add_child(titles)
	detail_title = UiTheme.label("", 26, UiTheme.TEXT)
	detail_title.add_theme_font_override("font", UiTheme.font_heading())
	detail_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	titles.add_child(detail_title)
	detail_chips = HFlowContainer.new()
	detail_chips.add_theme_constant_override("h_separation", 6)
	detail_chips.add_theme_constant_override("v_separation", 6)
	titles.add_child(detail_chips)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inner.add_child(scroll)
	detail = UiTheme.label("Bir eşya seç.", 18, UiTheme.TEXT_DIM)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(detail)
	actions = HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", 8)
	actions.add_theme_constant_override("v_separation", 8)
	inner.add_child(actions)

	var right := Screen.column(460)
	body.add_child(right)
	right.add_child(UiTheme.section("Depo / Bagaj"))
	stock_title = UiTheme.label("", 18, UiTheme.TEXT)
	stock_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(stock_title)
	stock_list = ItemList.new()
	stock_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stock_list.fixed_icon_size = Vector2i(36, 36)
	stock_list.item_selected.connect(func(i: int) -> void: _select(_stock_stacks[i], "stock"))
	right.add_child(stock_list)
	stock_note = UiTheme.label("", 15, UiTheme.MUTED)
	stock_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(stock_note)
	footer.text = "Eşya seç, sonra alttaki düğmelerle kullan / bırak / yuvaya ata. [N] hızlı ye · [U] hızlı iç. Depo yalnızca kapalı bir üssün içinde açılır."


func _stat(label: String, value: String, ratio: float, color: Color, note := "") -> PanelContainer:
	var card := UiTheme.card()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	card.add_child(box)
	var row := HBoxContainer.new()
	box.add_child(row)
	var name := UiTheme.eyebrow(label)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name)
	var shown := UiTheme.label(value, 20, color)
	shown.add_theme_font_override("font", UiTheme.font_strong())
	row.add_child(shown)
	if ratio >= 0.0:
		var meter := ProgressBar.new()
		meter.show_percentage = false
		meter.custom_minimum_size.y = 6
		meter.max_value = 1.0
		meter.value = clampf(ratio, 0.0, 1.0)
		meter.add_theme_stylebox_override("fill", UiTheme.box(color, 3))
		meter.add_theme_stylebox_override("background", UiTheme.box(Color(1, 1, 1, 0.06), 3))
		box.add_child(meter)
	if note != "":
		box.add_child(UiTheme.label(note, 14, UiTheme.MUTED))
	return card


func _base() -> Settlement:
	return game.bases.inside if game.bases != null else null


func _vehicle() -> Dictionary:
	if game.vehicles == null or _base() != null:
		return {}
	return game.vehicles.nearest(game.player.global_position, 3.5)


func _other() -> Inventory:
	## Sag panel: ussun ortak deposu ya da yanindaki aracin bagaji.
	var base := _base()
	if base != null:
		return base.stockpile
	var car := _vehicle()
	return car.trunk if not car.is_empty() else null


func refresh() -> void:
	var inventory: Inventory = game.inventory
	# Kisisel ihtiyaclar: deger, dusuk esige kalan sure (gercek dk, yuruyus) ve etkisi.
	var v: PlayerVitals = game.vitals
	var minutes := func(kind: String) -> String:
		var h: float = v.hours_until(kind, "walk")
		return "düşük eşik: şimdi" if h <= 0.0 else "düşük eşiğe ~%d dk" % int(ceil(h * 40.0 / 60.0))
	var effects := PackedStringArray()
	if v.stamina_cap() < 100.0:
		effects.append("nefes tavanı %d" % int(v.stamina_cap()))
	if v.regen_factor() < 1.0:
		effects.append("nefes yenilenmesi %%%d" % int(v.regen_factor() * 100))
	if v.statuses.has(PlayerVitals.SICK):
		effects.append("mide bulantısı: su hızlı gider")
	for child in stats.get_children():
		child.queue_free()
	var load_ratio := inventory.weight() / maxf(1.0, inventory.capacity_kg)
	stats.add_child(_stat("Çanta", "%.1f / %.0f kg" % [inventory.weight(), inventory.capacity_kg], load_ratio,
		UiTheme.BAD if inventory.overloaded() else UiTheme.ACCENT, "AĞIR: yavaşlıyorsun" if inventory.overloaded() else ""))
	stats.add_child(_stat("Yuva", "%d / %d" % [inventory.slots_used(), inventory.max_slots],
		float(inventory.slots_used()) / maxf(1.0, inventory.max_slots), UiTheme.INFO))
	stats.add_child(_stat("Zırh", "%.1f" % game.vitals.armor, -1.0, UiTheme.TEXT, "Kuşanılan zırh hasarı azaltır"))
	stats.add_child(_stat("Tokluk", "%d" % int(v.satiety), v.satiety / 100.0, Hud.FOOD, minutes.call("food")))
	stats.add_child(_stat("Su", "%d" % int(v.hydration), v.hydration / 100.0, Hud.WATER, minutes.call("water")))
	if not effects.is_empty():
		stats.add_child(_stat("Etkiler", "", -1.0, UiTheme.BAD, ", ".join(effects)))

	_bag_stacks = _sorted(inventory.stacks)
	_fill(bag_list, _bag_stacks, true)
	var base := _base()
	var car := _vehicle()
	var other := _other()
	stock_note.text = ""
	if base != null:
		stock_title.text = "%s ortak deposu · %.0f / %.0f kg" % [base.name, base.stockpile.weight(), base.stockpile.capacity_kg]
	elif not car.is_empty():
		stock_title.text = "%s bagajı · %.0f / %.0f kg" % [Vehicles.def_of(car).get("name", ""), car.trunk.weight(), car.trunk.capacity_kg]
		stock_note.text = "Yakıt %d/%d · sağlamlık %d" % [int(car.fuel), int(Vehicles.tank(car)), int(car.durability)]
	else:
		stock_title.text = "Depo kapalı"
		stock_note.text = "Ortak depo yalnızca kapalı bir üssün içinde açılır. Bir aracın yanındaysan bagajı burada görünür."
	_stock_stacks = _sorted(other.stacks) if other != null else []
	_fill(stock_list, _stock_stacks, false)
	if _selected != null and not (inventory.stacks.has(_selected) or (other != null and other.stacks.has(_selected))):
		_selected = null
	_show_detail()


static func _sorted(stacks: Array) -> Array:
	var order := {"weapon": 0, "ammo": 1, "consumable": 2, "tool": 3, "mod": 4, "station": 5,
		"assembly": 6, "component": 7, "material": 8}
	var result := stacks.duplicate()
	result.sort_custom(func(a: ItemStack, b: ItemStack) -> bool:
		var ca: int = order.get(a.definition.category, 9)
		var cb: int = order.get(b.definition.category, 9)
		if ca != cb:
			return ca < cb
		return a.definition.name < b.definition.name)
	return result


func _fill(list: ItemList, stacks: Array, show_slot: bool) -> void:
	list.clear()
	for stack: ItemStack in stacks:
		var text := "%s   ×%d   ·   %.1f kg" % [stack.display_name(), stack.quantity, stack.total_weight()]
		if show_slot:
			var slot: int = game.combat.slots.find(stack)
			if slot >= 0:
				text = "[%d]  %s" % [slot + 1, text]
		if stack.expires >= 0.0:
			var left: float = stack.expires - game.time.total_hours()
			text += "   (%s)" % ("%d sa içinde bozulur" % int(left) if left > 0.0 else "BOZULDU")
		# Model onizlemesinden uretilmis 128 px ikon (600 paket).
		var icon := AssetLibrary.icon(AssetLibrary.item_model_id(stack.definition))
		var index := list.add_item(text, icon)
		list.set_item_custom_fg_color(index, stack.color())


func _select(stack: ItemStack, source: String) -> void:
	_selected = stack
	_selected_from = source
	_show_detail()


func _show_detail() -> void:
	for child in actions.get_children():
		child.queue_free()
	for child in detail_chips.get_children():
		child.queue_free()
	for slot: String in game.equipment:
		var worn: ItemStack = game.equipment[slot]
		if worn != null:
			actions.add_child(UiTheme.button("Çıkar: %s" % worn.definition.name, func() -> void:
				game.hud.message(game.unequip(slot), Hud.ACCENT)
				refresh()))
	var car := _vehicle()
	if not car.is_empty():
		actions.add_child(UiTheme.button("Araca yakıt doldur", func() -> void:
			game.hud.message(game.vehicles.refuel(car, game.inventory), Hud.ACCENT)
			refresh()))
		actions.add_child(UiTheme.button("Aracı onar", func() -> void:
			game.hud.message(game.vehicles.repair(car, game.inventory), Hud.ACCENT)
			refresh()))
		var wrench := _salvage_tool()
		if wrench != null and not bool(car.get("salvaged", false)):
			actions.add_child(UiTheme.button("Aracı sök (%s)" % wrench.definition.name, func() -> void:
				var drops: Array = game.gathering.salvage_vehicle(car, wrench)
				if drops.is_empty():
					game.hud.message("Bu araçtan sökülecek bir şey çıkmadı", Hud.ACCENT)
				else:
					car.durability = 0.0
					car.fuel = 0.0
					game.combat.harvested.emit(drops, car.position + Vector3(0, 0.5, 0))
					game.on_noise_at(car.position, Units.perception_m(260.0))
				refresh()))
	if _selected == null:
		detail_title.text = "Bir eşya seç"
		detail_icon.texture = null
		detail.text = "Soldaki çantadan ya da sağdaki depodan bir eşya seç; özellikleri ve kullanım seçenekleri burada görünür."
		return
	var s := _selected
	detail_title.text = s.display_name()
	detail_icon.texture = AssetLibrary.icon(AssetLibrary.item_model_id(s.definition))
	detail_chips.add_child(UiTheme.chip(s.definition.category, UiTheme.TEXT_DIM))
	detail_chips.add_child(UiTheme.chip("T%d" % s.definition.tier, UiTheme.ACCENT))
	detail_chips.add_child(UiTheme.chip("%.2f kg / adet" % s.definition.weight, UiTheme.INFO))
	if s.definition.has_quality:
		detail_chips.add_child(UiTheme.chip("Kalite %d · %s" % [int(s.quality), ItemDef.quality_name(s.quality)], UiTheme.GOOD))
	var lines := PackedStringArray()
	if s.definition.durability > 0:
		lines.append("Dayanıklılık: %d / %d%s" % [s.durability, s.definition.durability, "  (BOZUK)" if s.broken() else ""])
	if s.definition.category == "weapon" and s.loaded > 0:
		lines.append("Şarjörde: %d fişek" % s.loaded)
	for mod: ItemStack in s.mods:
		lines.append("Mod: %s" % mod.display_name())
	if s.definition.category == "weapon" and s.ammo_id != "" and Content.item(s.ammo_id) != null:
		lines.append("Mermi: %s" % Content.item(s.ammo_id).name)
	var effects := ItemUsage.describe(s)
	if effects != "":
		lines.append(effects)
	var how := ItemUse.how_to(s.definition)
	if how != "":
		lines.append("")
		lines.append("Nasıl kullanılır: " + how)
	if s.definition.description != "":
		lines.append("")
		lines.append(s.definition.description)
	detail.text = "\n".join(lines)
	detail_chips.add_child(UiTheme.chip(ItemUse.CLASS_NAMES.get(ItemUse.classify(s.definition), ""), UiTheme.ACCENT))

	if _selected_from == "bag":
		var kind := ItemUse.classify(s.definition)
		if kind == "repair":
			actions.add_child(UiTheme.primary_button("Onar (kiti kullan)", func() -> void:
				game.hud.message(game.use_repair_kit(_selected), Hud.GREEN)
				refresh()))
		elif kind in ["consume"] or (s.definition.category == "consumable" and not s.definition.effects.is_empty() and kind != "throw"):
			var check := ItemUsage.can_use(s, game.vitals)
			var use := UiTheme.primary_button("Kullan", _use)
			use.disabled = not check[0]
			use.tooltip_text = check[1]
			actions.add_child(use)
		if s.definition.weapon_id != "":
			for i in PlayerCombat.SLOT_COUNT:
				actions.add_child(UiTheme.button("Yuva %d" % (i + 1), _assign.bind(i)))
		if s.definition.category == "weapon":
			for mod: ItemStack in s.mods:
				actions.add_child(UiTheme.button("Sök: %s" % mod.definition.name, func() -> void:
					game.hud.message(game.detach_mod(s, mod), Hud.ACCENT)
					refresh()))
			for other: ItemStack in game.inventory.stacks:
				if other.definition.category == "mod" and _mod_fits(other, s):
					actions.add_child(UiTheme.button("Tak: %s" % other.definition.name, func() -> void:
						game.hud.message(game.attach_mod(s, other), Hud.GREEN)
						refresh()))
		if s.definition.category == "mod":
			for weapon: ItemStack in game.inventory.stacks:
				if weapon.definition.category == "weapon" and _mod_fits(s, weapon):
					actions.add_child(UiTheme.primary_button("Tak → %s" % weapon.definition.name, func() -> void:
						game.hud.message(game.attach_mod(weapon, s), Hud.GREEN)
						_selected = null
						refresh()))
		if s.definition.category == "ammo":
			actions.add_child(UiTheme.primary_button("Bu mermiyi kullan", func() -> void:
				game.hud.message(game.select_ammo(s), Hud.GREEN)
				refresh()))
		if s.definition.equippable():
			actions.add_child(UiTheme.primary_button("Kuşan (%s)" % ItemDef.SLOT_NAMES.get(s.definition.slot, s.definition.slot), func() -> void:
				game.hud.message(game.equip_item(_selected), Hud.GREEN)
				_selected = null
				refresh()))
		if s.definition.category == "vehicle_part" and not car.is_empty():
			actions.add_child(UiTheme.primary_button("Araca tak", func() -> void:
				game.hud.message(game.vehicles.install_part(car, _selected, game.inventory), Hud.GREEN)
				_selected = null
				refresh()))
		if kind in ["place", "build"]:
			actions.add_child(UiTheme.primary_button("İnşa kipinde kur (B)", func() -> void:
				game.build.select_item(s.definition.id)
				close()))
		if s.definition.durability > 0 and s.durability < s.definition.durability:
			actions.add_child(UiTheme.button("Onar (tezgâh)", func() -> void:
				game.hud.message(game.repair_item(_selected), Hud.ACCENT)
				refresh()))
		if Content.graph.recipes_producing(s.definition.id).size() > 0 and s.definition.category != "consumable":
			var ratio := 0.75 if game.skills.has_behavior("salvage_plus") else CraftingService.DISASSEMBLE_RETURN
			actions.add_child(UiTheme.button("Sök (%%%d geri)" % int(ratio * 100), func() -> void:
				var r: Dictionary = game.crafting.disassemble(game.inventory, _selected, Content.recipes,
					Content.graph.produced_by, ratio)
				if r.success:
					var names := PackedStringArray()
					for piece: ItemStack in r.returned:
						names.append("%s ×%d" % [piece.definition.name, piece.quantity])
					game.hud.message("Söküldü: " + ", ".join(names), Hud.GREEN)
					_selected = null
				else:
					game.hud.message(str(r.reason), Hud.RED)
				refresh()))
		actions.add_child(UiTheme.button("Bırak", _drop))
		if _other() != null:
			actions.add_child(UiTheme.button("Depoya / bagaja koy ›", _transfer.bind(true)))
	elif _other() != null:
		actions.add_child(UiTheme.button("‹ Çantaya al", _transfer.bind(false)))


func _salvage_tool() -> ItemStack:
	for stack: ItemStack in game.inventory.stacks:
		if float(stack.definition.effects.get("harvest_vehicle", 0.0)) > 0.0 and not stack.broken():
			return stack
	return null


static func _mod_fits(mod: ItemStack, weapon: ItemStack) -> bool:
	var wdef: WeaponDef = Content.weapons.get(weapon.definition.weapon_id)
	if wdef == null:
		return false
	var fits := mod.definition.fits
	if fits.is_empty():
		return not wdef.is_melee()
	return wdef.category in fits or wdef.id in fits


func _use() -> void:
	var healing: bool = _selected.definition.effects.has("heal")
	var result := ItemUsage.use(_selected, game.vitals, game.inventory, game.skills, game.survival.rng)
	game.hud.message(result.message, Hud.GREEN if result.ok else Hud.RED)
	if result.ok and healing:
		game.progression.count("healed")
	if result.ok and float(result.get("xp", 0.0)) > 0.0:
		game.progression.award(float(result.xp))
	for key: String in result.get("unknown", []):
		push_warning("Bilinmeyen etki anahtari: %s (%s)" % [key, _selected.definition.id])
	refresh()


func _assign(slot: int) -> void:
	game.combat.assign_slot(slot, _selected)
	refresh()


func _drop() -> void:
	var stack: ItemStack = game.inventory.take_from_stack(_selected, _selected.quantity)
	if stack != null:
		game.pickups.spawn([stack], game.player.global_position + game.player.look_direction() * 0.8 + Vector3(0, 0.2, 0),
			"Bırakılan", "remnant")
	_selected = null
	refresh()


func _transfer(to_stock: bool) -> void:
	var other := _other()
	if other == null:
		return
	var source: Inventory = game.inventory if to_stock else other
	var target: Inventory = other if to_stock else game.inventory
	var moving := source.take_from_stack(_selected, _selected.quantity)
	if moving == null:
		return
	var left := target.add(moving)
	if left > 0:
		# Sigmayan kisim KAYNAGA geri doner: aktarim esya silmez.
		source.add(ItemStack.new(moving.definition, left, moving.quality, moving.durability))
		game.hud.message("%d adet sığmadı, yerinde kaldı" % left, Hud.RED)
	_selected = null
	refresh()
