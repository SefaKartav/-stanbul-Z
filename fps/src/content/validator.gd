class_name ContentValidator
extends RefCounted
## Tek bir icerik tanimini dogrular.
##
## Python surumundeki `schema.Validator`in karsiligi. GDScript'te istisna
## olmadigi icin hata FIRLATILMAZ, paylasilan listeye YAZILIR; kayit defteri
## yukleme sonunda liste bos degilse oyunu acmaz ve hatalari ekrana basar.
## Kural ayni kalir: yanlis yazilmis bir alan uc saat sonra crafting
## ekraninda degil, aciliste yakalanir.

var source: String
var id: String
var data: Dictionary
var errors: Array


func _init(p_source: String, p_id: String, p_data: Dictionary, p_errors: Array) -> void:
	source = p_source
	id = p_id
	data = p_data
	errors = p_errors


func fail(message: String) -> void:
	errors.append("%s: '%s' -> %s" % [source, id, message])


func text(key: String, default: Variant = null) -> String:
	var value: Variant = data.get(key, default)
	if value == null:
		fail("zorunlu alan eksik: " + key)
		return ""
	if typeof(value) != TYPE_STRING:
		fail("%s metin olmali" % key)
		return ""
	return value


func num(key: String, default: Variant = null, minimum: Variant = null, maximum: Variant = null) -> float:
	var value: Variant = data.get(key, default)
	if value == null:
		fail("zorunlu alan eksik: " + key)
		return 0.0
	# JSON'da bool da sayi gibi gorunebilir; Python surumu de bunu reddediyordu.
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		fail("%s sayi olmali" % key)
		return 0.0
	var number := float(value)
	if minimum != null and number < float(minimum):
		fail("%s en az %s olmali, %s geldi" % [key, minimum, number])
	if maximum != null and number > float(maximum):
		fail("%s en fazla %s olmali, %s geldi" % [key, maximum, number])
	return number


func integer(key: String, default: Variant = null, minimum: Variant = null) -> int:
	return int(num(key, default, minimum))


func flag(key: String, default: bool = false) -> bool:
	var value: Variant = data.get(key, default)
	if typeof(value) != TYPE_BOOL:
		fail("%s true/false olmali" % key)
		return default
	return value


func choice(key: String, options: Array, default: Variant = null) -> String:
	var value := text(key, default)
	if not options.has(value):
		fail("%s sunlardan biri olmali %s, '%s' geldi" % [key, options, value])
	return value


func text_list(key: String) -> PackedStringArray:
	var value: Variant = data.get(key, [])
	var result := PackedStringArray()
	if typeof(value) != TYPE_ARRAY:
		fail("%s metin listesi olmali" % key)
		return result
	for entry: Variant in value:
		if typeof(entry) != TYPE_STRING:
			fail("%s metin listesi olmali" % key)
			return PackedStringArray()
		result.append(entry)
	return result


func dict(key: String) -> Dictionary:
	var value: Variant = data.get(key, {})
	if typeof(value) != TYPE_DICTIONARY:
		fail("%s sozluk olmali" % key)
		return {}
	return value


func number_dict(key: String) -> Dictionary:
	## {"ad": sayi} bicimindeki alanlari float degerli sozluge cevirir.
	var raw := dict(key)
	var result := {}
	for name: Variant in raw:
		var value: Variant = raw[name]
		if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
			fail("%s['%s'] sayi olmali" % [key, name])
			continue
		result[str(name)] = float(value)
	return result


func color(key: String, default: Array) -> Color:
	var raw: Variant = data.get(key, default)
	if typeof(raw) != TYPE_ARRAY or raw.size() != 3:
		fail("%s [r,g,b] (0-255) olmali" % key)
		return Color.GRAY
	for channel: Variant in raw:
		if typeof(channel) != TYPE_FLOAT and typeof(channel) != TYPE_INT:
			fail("%s [r,g,b] (0-255) olmali" % key)
			return Color.GRAY
	return Color8(int(raw[0]), int(raw[1]), int(raw[2]))


func reject_unknown(known: Array) -> void:
	## Yazim hatasi yakalar: 'demage' yazip 0 hasar almak yerine hata al.
	var unknown: Array = []
	for key: Variant in data:
		if not known.has(key):
			unknown.append(key)
	if not unknown.is_empty():
		unknown.sort()
		fail("bilinmeyen alan(lar): %s" % [unknown])


static func load_json(path: String, errors: Array) -> Variant:
	## JSON dosyasini okur; hata olursa listeye yazar ve null dondurur.
	if not FileAccess.file_exists(path):
		errors.append("%s: dosya bulunamadi" % path)
		return null
	var text_data := FileAccess.get_file_as_string(path)
	var parser := JSON.new()
	var result := parser.parse(text_data)
	if result != OK:
		errors.append("%s: gecersiz JSON (satir %d) -- %s" % [
			path, parser.get_error_line(), parser.get_error_message()])
		return null
	return parser.data
