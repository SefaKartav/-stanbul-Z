class_name LootScreen
extends Screen
## Aranan mobilyanin icerigi (sol) ve oyuncunun cantasi (sag).
##
## Dolabi acmak esyayi OTOMATIK cantaya aktarmaz: oyuncu tek adet, yigin ya
## da kapasite yettigince hepsini alir. Sigmayan esya container'da KALIR ve
## sonra geri gelip alinabilir. Dunya DURMAZ (envanter gibi): zombi
## yaklasirken dolap karistirmak bir risktir. Oyuncu uzaklasirsa panel kapanir.

var plan: Dictionary
var f: Dictionary
var origin := Vector3.ZERO
var content_list: ItemList
var bag_list: ItemList
var capacity_label: Label
var detail: Label
var _stacks: Array = []


func _init() -> void:
	super._init()
	title = "Dolap"
	toggle_action = "interact"


func _build_content() -> void:
	var left := Screen.column(560)
	body.add_child(left)
	left.add_child(UiTheme.label("Icindekiler", 22, UiTheme.ACCENT))
	content_list = ItemList.new()
	content_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_list.item_activated.connect(func(_i: int) -> void: _take(0))
	content_list.item_selected.connect(func(_i: int) -> void: _show_detail())
	left.add_child(content_list)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	buttons.add_child(UiTheme.button("1 adet al", _take.bind(1)))
	buttons.add_child(UiTheme.button("Yigini al", _take.bind(0)))
	buttons.add_child(UiTheme.button("Tumunu al [R]", _take_all))
	left.add_child(buttons)
	detail = UiTheme.label("", 18, UiTheme.MUTED)
	left.add_child(detail)

	var right := Screen.column(520)
	body.add_child(right)
	capacity_label = UiTheme.label("", 22, UiTheme.ACCENT)
	right.add_child(capacity_label)
	bag_list = ItemList.new()
	bag_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(bag_list)
	footer.text = "Cift tik: yigini al.  Sigmayan esya dolapta kalir; sonra geri gelip alabilirsin.  [E]/[Esc] kapat."


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("reload"):
		get_viewport().set_input_as_handled()
		_take_all()
		return
	super._unhandled_input(event)


func _process(_delta: float) -> void:
	if game != null and game.player.global_position.distance_to(origin) > 3.0:
		close()


func refresh() -> void:
	_stacks = game.containers.items(f.id)
	var selected := content_list.get_selected_items()
	content_list.clear()
	for stack: ItemStack in _stacks:
		var index := content_list.add_item("%s  x%d   %.1f kg" % [stack.display_name(), stack.quantity, stack.total_weight()])
		content_list.set_item_custom_fg_color(index, stack.color())
	if _stacks.is_empty():
		content_list.add_item("(bos)")
		content_list.set_item_disabled(0, true)
	elif not selected.is_empty():
		content_list.select(mini(selected[0], _stacks.size() - 1))
	var inventory: Inventory = game.inventory
	capacity_label.text = "Canta: %.1f / %.0f kg  (kalan %.1f kg)   %d/%d yuva" % [inventory.weight(), inventory.capacity_kg,
		maxf(0.0, inventory.capacity_kg - inventory.weight()), inventory.slots_used(), inventory.max_slots]
	bag_list.clear()
	for stack: ItemStack in InventoryScreen._sorted(inventory.stacks):
		var index := bag_list.add_item("%s  x%d" % [stack.display_name(), stack.quantity])
		bag_list.set_item_custom_fg_color(index, stack.color())
	_show_detail()


func _show_detail() -> void:
	var selected := content_list.get_selected_items()
	if selected.is_empty() or selected[0] >= _stacks.size():
		detail.text = ""
		return
	var stack: ItemStack = _stacks[selected[0]]
	var usage := ItemUsage.describe(stack)
	detail.text = "%s -- %.2f kg/adet%s" % [stack.definition.description, stack.definition.weight,
		("\n" + usage) if usage != "" else ""]


func _take(count: int) -> void:
	var selected := content_list.get_selected_items()
	if selected.is_empty() or selected[0] >= _stacks.size():
		return
	var stack: ItemStack = _stacks[selected[0]]
	var name := stack.display_name()
	var result: Dictionary = game.containers.take(f.id, selected[0], count, game.inventory)
	if int(result.taken) > 0:
		game.hud.message("Alindi: %s x%d" % [name, result.taken], Hud.GREEN)
		game.sfx.play_ui("pickup")
	else:
		game.hud.message("Cantada yer yok: %s dolapta kaldi" % name, Hud.RED)
	refresh()


func _take_all() -> void:
	var before: int = game.containers.items(f.id).size()
	var result: Dictionary = game.containers.take_all(f.id, game.inventory)
	if not result.taken.is_empty():
		game.sfx.play_ui("pickup")
		var names := PackedStringArray()
		for stack: ItemStack in result.taken:
			names.append("%s x%d" % [stack.display_name(), stack.quantity])
		game.hud.message("Alindi: " + ", ".join(names), Hud.GREEN)
	var left: int = game.containers.items(f.id).size()
	if left > 0 and before > 0:
		game.hud.message("%d yigin sigmadi, dolapta kaldi" % left, Hud.RED)
	refresh()
