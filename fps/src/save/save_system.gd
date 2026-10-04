class_name SaveSystem
extends RefCounted
## Kayit dosyalari: yaz, oku, listele (Python: game/save/save_manager.py).
##
## DAYANIKLILIK KURALLARI (eski oyundan aynen + FPS eklemeleri)
##   1. ATOMIK YAZMA: once .tmp, sonra yerine tasima. Yarim dosya olmaz.
##   2. YEDEK: ustune yazmadan once eski dosya .bak olur.
##   3. BOZUK KAYIT: ana dosya okunamazsa .bak denenir. Hic okunamazsa dosya
##      SILINMEZ ve UZERINE YAZILMAZ: oyun "yukleme hatasi" bayragi tasir ve
##      otomatik kayit o yuvaya yazmaz (bkz. Game.load_failed).
##   4. SURUM: kayit bicimi, harita kimligi ve uretici surumu yazilir. Harita
##      ya da bicim uyumsuzsa kayit ACILMAZ, dosya korunur ve oyuncuya
##      anlasilir bir mesaj verilir. Kanitlanmamis uyumluluk vaat edilmez.
##
## Eski 2D oyunun kayitlari user://saves altindadir ve bu sinif onlara hic
## yazmaz; FPS kayitlari user://saves_fps altindadir.

const DIRECTORY := "user://saves_fps/"
const EXTENSION := ".izfps"
const FORMAT := "istanbulz-fps"
const VERSION := 3      # 3: 1:1 harita, kisisel ihtiyaclar, gorevler, beceri agaci; 1/2 -> 3 olcek gocu
                        # 2: container (mobilya) aramasi; 1 -> 2 goc tanimli
const AUTOSAVE := "autosave"
const QUICKSAVE := "quicksave"

var last_error := ""
# Testler gercek kayit klasorune yazmasin diye degistirilebilir.
var directory := DIRECTORY


func path_for(slot: String) -> String:
	return directory + slot + EXTENSION


func write(slot: String, data: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(directory)
	var target := path_for(slot)
	var temporary := target + ".tmp"
	var backup := target + ".bak"
	data["format"] = FORMAT
	data["version"] = VERSION
	data["saved_at"] = Time.get_unix_time_from_system()
	var file := FileAccess.open_compressed(temporary, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if file == null:
		last_error = "Kayit dosyasi acilamadi: %s" % error_string(FileAccess.get_open_error())
		return false
	file.store_string(JSON.stringify(data))
	file.close()
	# Yazilan dosya gercekten okunabiliyor mu? Okunamayan bir kaydi eski
	# kaydin yerine koymak, oyuncunun elindeki son saglam kaydi yok ederdi.
	if _read_file(temporary).is_empty():
		DirAccess.remove_absolute(temporary)
		last_error = "Yazilan kayit dogrulanamadi"
		return false
	if FileAccess.file_exists(target):
		if FileAccess.file_exists(backup):
			DirAccess.remove_absolute(backup)
		DirAccess.rename_absolute(target, backup)
	var error := DirAccess.rename_absolute(temporary, target)
	if error != OK:
		last_error = "Kayit yerine konamadi: %s" % error_string(error)
		return false
	last_error = ""
	return true


func read(slot: String) -> Dictionary:
	## Okunamazsa bos sozluk; sebebi `last_error`da.
	var target := path_for(slot)
	var data := _read_file(target)
	if not data.is_empty():
		return data
	var backup := target + ".bak"
	if FileAccess.file_exists(backup):
		data = _read_file(backup)
		if not data.is_empty():
			last_error = "Ana kayit bozuktu, bir onceki kayit (yedek) yuklendi"
			return data
	if FileAccess.file_exists(target):
		last_error = "Kayit okunamadi ve yedek yok; dosya korunuyor: %s" % ProjectSettings.globalize_path(target)
	else:
		last_error = "Kayit bulunamadi"
	return {}


func _read_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY or parsed.get("format", "") != FORMAT:
		return {}
	return parsed


func check_compatible(data: Dictionary, map_id: String, generator_version: int) -> String:
	## Bos dize = uyumlu. Aksi halde oyuncuya gosterilecek aciklama.
	var version := int(data.get("version", 0))
	if version > VERSION:
		return "Bu kayit oyunun daha yeni bir surumuyle yapilmis (v%d > v%d). Kayit korunuyor." % [version, VERSION]
	if version < 1:
		return "Kayit bicimi cok eski (v%d). Aktarim tanimli degil; kayit korunuyor." % version
	var world: Dictionary = data.get("world", {})
	if str(world.get("map_id", "")) != map_id:
		return "Kayit baska bir haritaya ait ('%s'). Kayit korunuyor." % world.get("map_id", "?")
	var saved_generator := int(world.get("generator_version", -1))
	# v1 kayit + uretici 1 -> 2: TANIMLI GOC (bina icleri eklendi; voxel
	# farklari ayni hucrelerde gecerli, kirilan yer kirik kalir; bina arama
	# haklari container durumuna cevrilir). Baska uyumsuzluk kabul edilmez.
	if version == 1 and saved_generator == 1 and generator_version == 2:
		return ""
	# OLCEK GOCU (uretici 1/2, 0.65 -> 3, 1:1): cografi donusumle tasinir;
	# kaynak dosya once yedeklenir (bkz. SaveMigration, Game._ready).
	if SaveMigration.applies(data, map_id, generator_version):
		return ""
	if saved_generator != generator_version:
		return ("Harita ureticisi degismis (kayit v%d, oyun v%d): kirilan/konan bloklarin yeri "
			+ "kayabilir. Kayit korunuyor; yeni oyun onerilir.") % [int(world.get("generator_version", -1)), generator_version]
	return ""


func backup_copy(slot: String, suffix: String) -> String:
	## Goc oncesi KAYNAK kaydin dokunulmamis kopyasi (varsa ustune yazmaz).
	var source := path_for(slot)
	var target := directory + slot + suffix + EXTENSION
	if not FileAccess.file_exists(source) or FileAccess.file_exists(target):
		return target if FileAccess.file_exists(target) else ""
	var bytes := FileAccess.get_file_as_bytes(source)
	var file := FileAccess.open(target, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_buffer(bytes)
	file.close()
	return target


func exists(slot: String) -> bool:
	return FileAccess.file_exists(path_for(slot)) or FileAccess.file_exists(path_for(slot) + ".bak")


func info(slot: String) -> Dictionary:
	var data := read(slot)
	if data.is_empty():
		return {}
	var time_data: Dictionary = data.get("time", {})
	var normalized := float(time_data.get("normalized", 0.0))
	var minutes := int(normalized * 24 * 60)
	return {"slot": slot, "day": int(time_data.get("day", 1)),
		"clock": "%02d:%02d" % [minutes / 60, minutes % 60],
		"saved_at": float(data.get("saved_at", 0.0)),
		"map": str(data.get("world", {}).get("map_id", ""))}


func list_slots() -> Array:
	var result: Array = []
	if not DirAccess.dir_exists_absolute(directory):
		return result
	for file_name in DirAccess.get_files_at(directory):
		if file_name.ends_with(EXTENSION):
			var entry := info(file_name.trim_suffix(EXTENSION))
			if not entry.is_empty():
				result.append(entry)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.saved_at > b.saved_at)
	return result


# --- eski 2D kayitlari ---
const LEGACY_DIRECTORY := "user://saves/"


func legacy_slots() -> PackedStringArray:
	var result := PackedStringArray()
	if DirAccess.dir_exists_absolute(LEGACY_DIRECTORY):
		for file_name in DirAccess.get_files_at(LEGACY_DIRECTORY):
			if file_name.ends_with(".izsave"):
				result.append(file_name.trim_suffix(".izsave"))
	return result


func read_legacy(slot: String) -> Dictionary:
	## Eski kaydi SALT OKUR (IZ1 imzasi + zlib). Dosyaya asla yazmaz.
	var path := LEGACY_DIRECTORY + slot + ".izsave"
	var raw := FileAccess.get_file_as_bytes(path)
	if raw.size() < 4 or raw.slice(0, 3).get_string_from_ascii() != "IZ1":
		last_error = "Eski kayit imzasi taninmadi"
		return {}
	var inflated := raw.slice(3).decompress_dynamic(64 * 1024 * 1024, FileAccess.COMPRESSION_DEFLATE)
	var parsed: Variant = JSON.parse_string(inflated.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		last_error = "Eski kayit cozulemedi"
		return {}
	return parsed
