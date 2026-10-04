# Doğrulama raporu

- Eski paket manifesti `manifest_combined_600.json` üzerinden okundu: 600 kayıt, yeni `iz2_` ailesi dahil.
- Yeni ana varlık: 360 GLB; ID'ler benzersiz `iz3_` önekiyle.
- GLB başlık/chunk yapısı, JSON parse, buffer/accessor sayımları, pozitif metre ölçeği, koordinat sınırları ve SHA-256 üretim sırasında doğrulandı.
- Üçgen sayıları gerçekten yazılan mesh index sayısından hesaplandı. Vertex color paleti GLB PBR materyaliyle birlikte gömülüdür.
- Collider önerileri ve marker'lar `interaction_metadata_soft.json` içinde açıkça bulunur; Godot uygulaması bu pakette çalıştırılmadı.
- LOD dosyaları üretilmedi; mevcut bu oluşturucuda güvenilir otomatik mesh sadeleştirici yok. LOD alanları boş liste.
- Zombi klipleri kısıtlı prosedürel eklem rotasyon taslağıdır; `idle/walk/run/attack/hit/death` üretim seviyesinde dikişsiz animasyon seti bu pakette tamamlanmadı. Otomatik retarget iddiası yok.
- Önizleme/katalog, GLB meshlerinden türetilen model kutu geometrisi ve palet kullanılarak oluşturuldu; harici render motoru veya Godot testi yapılmadı.
- Üretilen varlıklar low-poly modüler oyun prototipleri olarak kullanılabilir; mimari ve kurum sahnelerindeki bazı modüller basitleştirilmiş geometridir.

- Kategori sayımı: mahalle 60, tarihî 36, askerî 30, sağlık 36, okul 24, hapishane 24, üretim 48, inşa/savunma 36, çevre/ulaşım 30, zombi/elde kullanılan 36.
