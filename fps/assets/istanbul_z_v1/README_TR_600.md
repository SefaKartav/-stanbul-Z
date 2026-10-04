# Istanbul-Z — 600 Model Asset Paketi

Bu sürüm önceki **300 GLB’yi bayt olarak aynen korur** ve CSV’deki **300 yeni `iz2_` modelini** ekler. Toplam 600 benzersiz ID ve 600 ana GLB vardır. SVG, PNG, animasyon, LOD ve örnek sahneler bu sayıya dahil değildir.

## Hızlı kullanım

ZIP’i çıkardıktan sonra `CATALOG_600.html` dosyasını tarayıcıda açın. Katalog çevrimdışıdır; ad ve kategoriyle aranabilir, her kaydın gerçek GLB’sine bağlantı verir. Claude Code’a bu dosyayla birlikte `CLAUDE_ENTEGRASYON_600.md`, `manifest_expansion_600.json` ve `interaction_metadata_expansion.json` verin.

## Yeni modeller

Her kategoride 25 olmak üzere: `vertical_access`, `interior_structure`, `facade_roof`, `street_road`, `water_food`, `survival_items`, `power_logistics`, `special_interiors`, `mission_props`, `characters`, `equipment_defense`, `district_identity`.

Modeller metre ölçeğinde, +Y yukarı ve −Z ileri eksenindedir. Mat vertex color malzemesi kullanılır. Cam gereken yeni modellerde `glass_clear` ayrı materyal ve node’dur. Her yeni modelin geometri düzeni ve ölçüsü ayrıdır; yalnız renk değiştirilerek yeni kayıt sayılmamıştır.

## Manifestler

- `manifest.json`: ilk 94 kayıt, korunmuş dosya.
- `manifest_additions.json`: sonraki 206 kayıt, korunmuş dosya.
- `manifest_combined_300.json`: önceki 300 kayıt, korunmuş dosya.
- `manifest_expansion_600.json`: yalnız 300 yeni model.
- `manifest_combined_600.json`: doğrulanmış 600 model.
- `interaction_metadata_expansion.json`: kullanım türü, marker, collider önerisi, malzeme/HP sınıfı ve hareket bilgisi.
- `source_geometry_expansion.json`: 300 yeni modelin yeniden üretilebilir küboid geometrisi.

Collider verileri öneridir; GLB’ye fizik gömülü değildir. Collider kutuları ilgili node’un yerel uzayındadır. `material_id`, `hp_class` ve `bullet_surface` oyun verisindeki malzeme sistemiyle eşlenmelidir; asset paketi kesin HP dengesi belirlemez.

## Merdiven ve yapı parçaları

Düz, L, U ve spiral merdivenler ayrı geometridir. L/U modellerinde iki kol ve sahanlık bulunur. `stair_entry`, `stair_exit` ve uygun modelde `landing` marker’ları vardır. Metadata 2.8/3.0/3.2 m kat yüksekliği için parametrik kaynak hedefini, 2.05 m minimum baş boşluğunu ve varsayılan yürünebilir genişliği kaydeder. Hazır GLB varsayılan yaklaşık 3 m kat yüksekliği içindir; başka yüksekliği oyun içinde rastgele scale etmek yerine `tools/build_expansion_600.py` kaynak ölçülerinden yeniden üretin.

Duvar ve döşeme parçaları büyük kapalı bina prefabı değildir. OSM ayak izi, oda kurulumu, yıkılabilir voxel dünya ve yol üretimi oyun kodunda kalır. `snap_*`, kapı, merdiven ve montaj marker’larını wrapper sahnelerde Marker3D’ye dönüştürebilirsiniz.

## Karakterler

Yeni 25 karakter rigid parçalı node sistemini kullanır. Hepsinde `idle`, `walk`, `attack`, `hit`, `death`; survivor modellerinde `interact` ve `carry`; zombi modellerinde `run` klibi vardır. Bunlar iskeletli/skinned mesh değildir. Meslek ekipmanı ayrı `equipment` node’undadır. Ortak parçalar: `torso`, `head`, `left_leg`, `right_leg`, `left_arm`, `right_arm`.

## Yardımcı içerik

- `textures_16/`: döşenebilir 16×16 asfalt, kaldırım, bordür, taş, beton, tuğla, sıva, parke, fayans, metal ve çatı dokuları.
- `decals/`: yol çizgisi, çatlak ve leke; döşenebilir blok dokularından ayrıdır.
- `icons_128/`: 600 model için gerçek model önizlemesinden ikon.
- `ui_icons/`: tokluk, hidrasyon, stamina, kirli su, bozulma ve görev simgeleri.
- `signs_svg_600/`: düzenlenebilir Türkçe SVG tabelalar.
- `sample_scenes/`: üç kat erişim, su köşesi, altyapı/görev alanı ve karakter sırası için ölçülü JSON yerleşim referansları. Bunlar motor sahnesi veya GLB sayılmaz.
- `catalogs_600/`: kategori görsel tabloları.

## Doğrulama ve sınırlar

600 GLB’nin başlık, byte uzunluğu, buffer sınırı, indeks aralığı, gerçek geometri bounds’u, üçgen sayısı, SHA-256 ve animasyon hedefleri kontrol edildi. 300 eski model ve eski üç manifest kaynak paketle bayt olarak aynı kaldı. CSV’deki 300 yeni ID eksiksiz, çakışmasız ve kategori başına 25’tir. Yeni modeller arasında birebir aynı geometri yoktur.

Godot ve Blender bu ortamda kurulu olmadığı için motor importu, navigasyon, animasyon sırasında collider davranışı, cam sıralaması ve RTX 2050 performansı denenmedi. Önizlemeler gerçek GLB geometrisinden yazılım renderer ile alınmıştır. Küboid kaynak, kapalı iç yüzeyleri tam optimize etmez; yoğun sahnede instancing, birleştirme ve LOD profili uygulanmalıdır. Ses dosyası üretilmedi; `SOUND_NEEDS.md` ihtiyaç listesidir.
