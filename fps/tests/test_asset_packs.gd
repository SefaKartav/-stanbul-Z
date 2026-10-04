extends RefCounted
## Ek asset paketleri (istanbul_z_soft_expansion, iz3_) ve arayuz yazi
## tipleri: paket kendi kokunden okunur, eski 600 kimlik korunur, hareket
## metadatasi eski bicime cevrilir, fontlar yedek fonta dusmez.

const SOFT_DIR := "res://assets/istanbul_z_soft_expansion/"


func test_soft_pack_loads_beside_old_pack(t) -> void:
	if not DirAccess.dir_exists_absolute(SOFT_DIR):
		t.ok(true, "yumusak genisleme paketi yok: atlandi")
		return
	t.ok(AssetLibrary.count() >= 960, "600 eski + 360 yeni kayit (%d)" % AssetLibrary.count())
	t.ok(AssetLibrary.has("pistol"), "eski kimlik korunur")
	t.eq(AssetLibrary.pack_dir("pistol"), AssetLibrary.PACK_DIR, "eski kimlik eski paketten")
	var id := "iz3_neighborhood_cephe_dar"
	t.ok(AssetLibrary.has(id), "yeni kimlik okunur")
	t.eq(AssetLibrary.pack_dir(id), SOFT_DIR, "yeni kimlik kendi kokunden")
	t.ok(AssetLibrary.scene(id) != null, "yeni model sahnesi yuklenir")
	t.ok(AssetLibrary.icon(id) != null, "yeni ikon icon_path'ten yuklenir")
	var missing := AssetLibrary.missing_files.filter(func(m: String) -> bool: return m.begins_with("iz3_"))
	t.eq(missing.size(), 0, "iz3_ dosyalari eksiksiz: %s" % str(missing.slice(0, 5)))
	var clashes := AssetLibrary.collisions.filter(func(c: String) -> bool: return c.contains("soft"))
	t.eq(clashes.size(), 0, "yeni paket eski kimlik ezmez: %s" % str(clashes.slice(0, 3)))


func test_soft_pack_motion_metadata_is_normalized(t) -> void:
	if not DirAccess.dir_exists_absolute(SOFT_DIR):
		t.ok(true, "yumusak genisleme paketi yok: atlandi")
		return
	var door := "iz3_neighborhood_kapı_dar"
	var motions: Dictionary = AssetLibrary.metadata(door).get("motions", {})
	t.ok(motions.has("door_leaf"), "part_motion -> motions")
	t.eq(str(motions.get("door_leaf", {}).get("path", "")), "rotation", "eksen+aci -> rotation")


func test_ui_fonts_are_bundled(t) -> void:
	# Proje varsayilan fontu da Barlow oldugundan yedek fontla karsilastirilmaz;
	# kaynak yolu denetlenir.
	t.eq(UiTheme.font_body().resource_path, "res://assets/fonts/Barlow-Medium.ttf", "govde fontu paketten")
	t.eq(UiTheme.font_strong().resource_path, "res://assets/fonts/Barlow-SemiBold.ttf", "kalin font paketten")
	t.eq(str(ProjectSettings.get_setting("gui/theme/custom_font")), "res://assets/fonts/Barlow-Medium.ttf", "proje fontu")
	t.ok(UiTheme.get_theme().default_font != null, "tema varsayilan fontu")


func test_turkish_upper(t) -> void:
	t.eq(UiTheme.upper("bir tarif seç"), "BİR TARİF SEÇ", "i -> İ")
	t.eq(UiTheme.upper("çıkış"), "ÇIKIŞ", "ı -> I")
