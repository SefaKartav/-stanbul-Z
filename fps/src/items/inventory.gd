class_name Inventory
extends RefCounted
## Agirlik sinirli yigin listesi.
##
## Izgara (Tetris) degil AGIRLIK: yuzlerce malzemeli bir oyunda izgara
## saatlerce yer degistirme isi olurdu. Asiri yuklenme yasak degil
## CEZALIDIR; kademeli yavaslama karar vermeyi surdurulebilir kilar.
## (Python: game/items/inventory.py)

const OVERLOAD_SLOWDOWN_PER_KG := 0.035
const MIN_SPEED_FACTOR := 0.35

signal changed

var stacks: Array = []          # Array[ItemStack]
var capacity_kg: float = 45.0
var max_slots: int = 60


func _init(p_capacity_kg: float = 45.0, p_max_slots: int = 60) -> void:
	capacity_kg = p_capacity_kg
	max_slots = p_max_slots


# --- olcumler ---
func weight() -> float:
	var total := 0.0
	for stack: ItemStack in stacks:
		total += stack.total_weight()
	return total


func overloaded() -> bool:
	return weight() > capacity_kg


func speed_factor() -> float:
	var excess := weight() - capacity_kg
	if excess <= 0.0:
		return 1.0
	return maxf(MIN_SPEED_FACTOR, 1.0 - excess * OVERLOAD_SLOWDOWN_PER_KG)


func slots_used() -> int:
	return stacks.size()


func full() -> bool:
	return stacks.size() >= max_slots


# --- ekleme / cikarma ---
func add(stack: ItemStack) -> int:
	## Yigini ekler. YERLESTIRILEMEYEN adedi dondurur (0 = hepsi girdi).
	## Not: gelen yiginin `quantity` alani tuketilir (Python ile ayni).
	if stack.quantity <= 0:
		return 0
	for existing: ItemStack in stacks:
		if existing.merge(stack) > 0 and stack.quantity <= 0:
			changed.emit()
			return 0
	while stack.quantity > 0 and not full():
		var portion := mini(stack.quantity, stack.definition.stack)
		stacks.append(stack.copy(portion))
		stack.quantity -= portion
	changed.emit()
	return stack.quantity


func remove(item_id: String, amount: int, min_quality: float = 0.0) -> Array:
	## Istenen adedi cikarir; DUSUK KALITEDEN once harcanir.
	var taken: Array = []
	var remaining := amount
	var candidates := stacks.filter(func(s: ItemStack) -> bool:
		return s.definition.id == item_id and s.quality >= min_quality)
	candidates.sort_custom(_by_quality)
	for stack: ItemStack in candidates:
		if remaining <= 0:
			break
		var take := mini(remaining, stack.quantity)
		taken.append(stack.copy(take))
		stack.quantity -= take
		remaining -= take
	compact()
	return taken


func remove_stack(stack: ItemStack) -> bool:
	var index := stacks.find(stack)
	if index < 0:
		return false
	stacks.remove_at(index)
	changed.emit()
	return true


func take_from_stack(stack: ItemStack, amount: int) -> ItemStack:
	## Belirli bir yigindan `amount` adet ayirir (birakma/aktarma icin).
	if not stacks.has(stack) or amount <= 0:
		return null
	amount = mini(amount, stack.quantity)
	var part := stack.copy(amount)
	stack.quantity -= amount
	compact()
	return part


func compact() -> void:
	stacks = stacks.filter(func(s: ItemStack) -> bool: return s.quantity > 0)
	changed.emit()


# --- sorgular ---
func count(item_id: String, min_quality: float = 0.0) -> int:
	var total := 0
	for stack: ItemStack in stacks:
		if stack.definition.id == item_id and stack.quality >= min_quality:
			total += stack.quantity
	return total


func count_by_tag(tag: String, min_quality: float = 0.0) -> int:
	var total := 0
	for stack: ItemStack in stacks:
		if stack.definition.has_tag(tag) and stack.quality >= min_quality:
			total += stack.quantity
	return total


func matching_tag(tag: String, min_quality: float = 0.0) -> Array:
	## Tag sorgusunu karsilayan yiginlar, KALITEYE gore artan sirada.
	var result := stacks.filter(func(s: ItemStack) -> bool:
		return s.definition.has_tag(tag) and s.quality >= min_quality and s.quantity > 0)
	result.sort_custom(_by_quality)
	return result


func find(item_id: String) -> ItemStack:
	for stack: ItemStack in stacks:
		if stack.definition.id == item_id:
			return stack
	return null


func by_category(category: String) -> Array:
	return stacks.filter(func(s: ItemStack) -> bool: return s.definition.category == category)


func clear() -> void:
	stacks.clear()
	changed.emit()


func clone() -> Inventory:
	## Derin kopya: "once kopyada dene" islemleri icin (bkz. crafting, koloni).
	var copy := Inventory.new(capacity_kg, max_slots)
	for stack: ItemStack in stacks:
		copy.stacks.append(stack.copy())
	return copy


func replace_with(other: Inventory) -> void:
	## Kopyada basarili olan islemi asil envantere tek adimda uygular.
	stacks = other.stacks
	changed.emit()


static func _by_quality(a: ItemStack, b: ItemStack) -> bool:
	return a.effective_quality() < b.effective_quality()


func to_dict() -> Dictionary:
	var data: Array = []
	for stack: ItemStack in stacks:
		data.append(stack.to_dict())
	return {"capacity_kg": capacity_kg, "max_slots": max_slots, "stacks": data}


func load_dict(data: Dictionary, items: Dictionary) -> void:
	stacks.clear()
	capacity_kg = float(data.get("capacity_kg", capacity_kg))
	max_slots = int(data.get("max_slots", max_slots))
	for entry: Variant in data.get("stacks", []):
		if typeof(entry) == TYPE_DICTIONARY:
			var stack := ItemStack.from_dict(entry, items)
			if stack != null:
				stacks.append(stack)
	changed.emit()
