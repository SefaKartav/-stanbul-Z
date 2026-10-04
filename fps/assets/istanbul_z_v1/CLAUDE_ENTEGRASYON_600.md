# Claude Code entegrasyonu — 600 model

Önce proje talimatlarını ve gerçek asset yükleyicisini incele. Eski `manifest.json` ve `manifest_additions.json` kullanımını koru. Yeni 300 kaydı `manifest_expansion_600.json` üzerinden, ID çakışması ve dosya varlığı kontrolünden sonra ekle. `manifest_combined_600.json` inceleme ve toplu katalog içindir; mevcut manifestleri sessizce ezme.

1. Paketi örneğin `fps/assets/istanbul_z_600/` altına al. GLB vertex color, metre ölçeği, +Y ve −Z yönünü bir örnekle doğrula.
2. `interaction_metadata_expansion.json` oyun tarafından otomatik desteklenmez. Marker node’larını Marker3D’ye ve collider önerilerini proje sahnelerine dönüştüren açık bir import adımı yaz.
3. Yapı parçalarında `material_id` ve `hp_class` değerlerini mevcut voxel malzeme tablosuna eşle. GLB tek başına yıkılabilir dünya hücresi değildir.
4. Merdivenleri gerçek karakter kapsülüyle test et: giriş/çıkış marker’ı, basamak, sahanlık, 2.05 m baş boşluğu, korkuluk ve kat kapısı. 2.8/3.0/3.2 m varyantlarını kaynak üreticiden oluştur; aynı GLB’yi dikey esnetme.
5. Container veya hareketli parça varsa node pivotunu ve `open`/`close` klibini koru. Loot oyun tarafından ayrı yerleştirilir.
6. Karakterlerde rigid node animasyonlarını kullan; Skeleton3D retarget varsayma. Ekipman node’unu rol değişiminde gizleyebilir/değiştirebilirsin.
7. Önce küçük kabul sahnesi kur: U merdiven, ince duvar, su arıtıcı, görev terminali ve bir survivor/zombi. Sonra üç kat yerleşim, su hazırlama ve altyapı sahnelerini `sample_scenes/*.json` üzerinden kur.
8. Statik tekrar eden parçalarda instancing, uzak modellerde LOD ve collider sadeleştirmesi uygula. Performansı hedef donanımda ölçmeden başarı yazma.

Kabulte 600 benzersiz ID, 600 GLB, eski 300 hash eşitliği, yeni 300 dosya, doğru yollar, çalışan animasyon referansları ve gerçek motor import ekran görüntüsü raporlanmalıdır. `validation_report_600.json` yalnız dosya/geometri kontrolüdür.
