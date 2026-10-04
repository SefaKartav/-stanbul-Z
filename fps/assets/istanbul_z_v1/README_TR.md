# Istanbul-Z — 300 Model / Genişletilmiş Voxel Asset Paketi

**94 önceki GLB aynen korundu + 206 yeni GLB = 300 ayrı 3D model.**
Önceki 12 SVG tabela ayrıca dahildir; 300 sayısına tabela, ikon, önizleme veya animasyon dahil edilmedi.

Kübik, düşük poligonlu ve mat görsel dil önceki paketle aynıdır. Ekran görüntüsündeki FPS oyunu ve yeni iç mekân/araç brief'i esas alınmıştır. Modeller gerçek glTF 2.0 / GLB dosyalarıdır, PNG sprite değildir.

## Önce bunları aç

1. ZIP'i bir klasöre çıkart.
2. **CATALOG.html** dosyasını tarayıcıda aç: 300 model arasında ad/kategori araması, GLB bağlantıları, açılabilir mobilyaların açık hâlleri ve araç içi görüş bağlantıları bulunur. İnternet gerekmez. Bu katalogda gömülü etkileşimli 3D görüntüleyici yoktur; GLB'yi Godot/Blender'a aktar.
3. **OVERVIEW_300.png** yeni modellerden seçilmiş bir genel görünüm gösterir. `catalogs/` içinde tüm modellerin kategori bazlı görsel listeleri var. `CATALOG.png` önceki 94 modelin korunmuş eski görselidir.
4. Claude'a paketle birlikte **CLAUDE_ENTEGRASYON.md** dosyasını ver.

## 206 yeni modelin dağılımı

| Klasör | Adet | İçerik |
|---|---:|---|
| models/interiors | 101 | Ev mobilyaları, mutfak/banyo, aydınlatma, elektronik, sağlık, berber, atölye |
| models/containers | 49 | Açılabilir dolaplar, sandıklar, çekmeceler; boş raflar ve bankolar |
| models/vehicle_interiors | 6 | Sedan, taksi, polis, van, minibüs ve ambulans kabinleri |
| models/vehicles_open | 6 | Aynı araçların boş iç hacimli dış kabukları |
| models/vehicle_parts | 20 | Koltuklar, motor, direksiyon, radyatör, lastik, ayna, vites vb. |
| models/props | 24 | Çaydanlık, bardak, tabak, havlu, kitap, yastık, temizlik ve ev eşyaları |

50 yeni modelde `open` / `close` klipleri vardır; kapı/kapak/drawer gibi hareketli parçalar ayrı node'lardır. Bunlara ek olarak eski 10 karakterin animasyonları da korunmuştur. Açık rafların animasyonu yoktur.

## Dosya düzeni

- **manifest.json:** Eski manifest değiştirilmeden korunmuştur; yalnız eski 94 modeli listeler.
- **manifest_additions.json:** Yalnız 206 yeni kayıt. Entegrasyon için esas ek liste.
- **manifest_combined_300.json:** 300 modeli birlikte gösteren yardımcı liste. Projenizin manifestinin üzerine kendiliğinden yazılmaz.
- **interaction_metadata.json:** Marker konumları, parça bazlı collider önerileri, hareket eksenleri, montaj yükseklikleri. Bu yeni sözleşme oyun tarafından otomatik okunmaz.
- **vehicle_compatibility.json / VEHICLE_COMPATIBILITY.md:** Her dış kabuk ve kabin için bire bir eşleme.
- **previews/:** Model başına PNG; eski 94 önizleme de korunmuştur.
- **previews_open/:** Yeni açılabilir container modellerinin GLB animasyonundan hesaplanan açık hâlleri.
- **icons_128/:** 300 model için 128×128 şeffaf PNG ikon; model sayısına eklenmez.
- **driver_views/:** 6 kabin × ileri/sol/sağ = 18 sürücü görüşü.
- **source_geometry.json:** Eski geometrinin korunmuş kaynağı.
- **source_geometry_additions.json:** Yeni küboid geometrisi, palette, marker, pivot ve hareket tanımları.
- **tools/build_expansion.py:** 206 yeni GLB'yi yeniden üretir. Eski modele/manifestine dokunmaz.
- **tools/render_validate.py:** GLB dosyalarını okur, kontrol eder ve katalog/test görsellerini üretir.
- **tools/build_v1_reference.py:** Önceki üreticinin referans kopyasıdır; bu yeni paket üzerinde çalıştırmayın.
- **validation_report.json / preservation_report.json:** Dosya ve eski paket korunma kontrolleri.
- **legacy_docs/:** Eski README ve entegrasyon notları; yeni iç mekân kararlarında güncel README önceliklidir.

Kaynak üreticiler Python 3 + NumPy + Pillow kullanır. Önizleme yazı tipi yolu Linux DejaVu Sans'tır; başka işletim sisteminde FONT yolunu uyarlayın. Hazır GLB'leri kullanmak için Python gerekmez.

## Teknik sözleşme

- Birim **metre**, yukarı **+Y**, ön **−Z**. Statik mobilyalar genellikle zemin merkezine göre yapılmıştır. Duvara/tavana takılan parçalarda metadata montaj yüksekliğini gösterir; tavan aksesuarlarında askı kökün altında kalabilir.
- Sert normaller, mat vertex color yüzeyleri. PNG texture bağımlılığı yoktur. Renkleri kullanan materyali devre dışı bırakmayın.
- Yeni pencere/kapı camları ayrı mesh ve `glass_clear` adlı saydam materyaldir (`alphaMode=BLEND`, alfa 0.09). Cam mesh'i kaldırıldığında açıklığı kapatan başka cam poligonu yoktur. Televizyon ekranı ve ayna stilize opak yüzeydir, pencere sayılmaz; gerçek ayna yansıması yoktur.
- Ölçüler yeni GLB içindeki gerçek float32 pozisyonlardan hesaplanmıştır. Eski manifestin ölçülerinde önceki sürümden kalan 0.001 m yuvarlama korunmuştur.
- Açılır nesneler boş kabuk olarak hazırlanmıştır. Raflarda kalıcı yiyecek/ilaç/silah yoktur. Eşya modellerini ayrı yerleştirin ve toplandığında kaldırın.
- Ön tarafta `interaction_anchor` vardır; Package A'nın 15 zorunlu asseti dahildir. Her mobilya tek envanter olarak ele alınabilir; çekmece başına otomatik loot üretmeyin.
- Collider'lar GLB'ye gömülmemiştir. Yan JSON kutuları her ilgili node'un yerel uzayındadır; animasyonla birlikte hareket ettirilmelidir. İnce levhalar ve açık kapı çerçevelerinin arası boş kalır. Motor performansına göre güvenli collider birleştirmesi yapın; kapı açıklıklarını/dolap içini büyük bir bounds collider ile kapatmayın.
- Yeni `open` / `close` animasyonları 0.7 saniyelik örnek kliplerdir. Döngü kapalı olmalı. Hareketin oyun içi engel/çarpışma kontrolü ayrıca gerekir. Node animasyonlarıdır; skinned mesh/iskelet değildir.

## Araçlar: birlikte kullanılması gerekenler

Eski `sedan`, `taxi`, `police_car`, `van`, `minibus`, `ambulance` modelleri **dolu kabin ve opak cam içerir**. Onlara yalnız yeni kabin eklemek sürüş görüşünü düzeltmez.

Sürülebilir sahnede ilgili **`*_shell_open` + `*_cabin`** çiftini kullanın. Aynı kök transform altında konum (0,0,0), quaternion (0,0,0,1), ölçek (1,1,1) ile eşleşirler; eski dolu modeli bu sahnede gizleyin. Eski model dosyaları silinmedi/değişmedi. Altı aracın ölçüsü farklı olduğundan kabinler bire bir üretildi; sedan kabini taksi/polis için göz kararı ölçeklenmez.

Kabinlerde `driver_eye`, `driver_seat`, `exit_left`, `exit_right`, `windshield_center` gerçek boş glTF node'ları bulunur. Direksiyon soldadır. `steering_wheel`, `speedometer_needle`, `fuel_needle`, `gear_lever`, `handbrake` ayrı parçalardır. Gösterge değeri sabit bir texture'a yazılmamıştır. Direksiyon ve ibreleri kendi yerel Z ekseninde koddan döndürebilirsiniz. Rakamlı hız göstergesi UI entegrasyonudur.

## Görüş ve doğrulama

18 görüş görüntüsü gerçek dış kabuk + kabin GLB geometrisinden, gerçek `driver_eye` noktasından, **82 derece yatay FOV** ve 16:9 oranla CPU z-buffer renderer kullanılarak üretildi. Sol/sağ yönleri ±60 derece yaw'dır. Test sahnesinde yol çizgileri, kaldırımlar, binalar ve engeller bulunur. Cam gizlenerek gerçek açıklık kontrol edildi; bu resimler cam materyalinin motor içi sıralamasını doğrulamaz. Sürücü gözünün opak geometri içinde olmadığı sayısal olarak kontrol edildi.

300 GLB'nin başlık/buffer/indeks/animasyon referansları, üçgen sayıları, hash'leri ve geometri sınırları kontrol edildi. Eski 94 GLB, manifest ve SVG tabelaların bayt olarak aynı kaldığı ayrıca doğrulandı. Önizlemeler geometri dosyalarından alınmıştır.

**Godot/Blender bu ortamda bulunmadığından oyun motorunda import, oynanış, cam render sıralaması, collider ve FPS performansı test edilmedi.** Paketi doğrudan bitmiş oyun sistemi olarak değerlendirmeyin. Gövde ve mobilya küboidlerinin içte kalan yüzleri tamamen temizlenmemiştir; chunk/LOD/instancing entegrasyonu gerekebilir. Bazı basit modeller bütçenin altında üçgen sayısına sahiptir; boş yere çokgen eklenmedi.

Bina kabuğu, döşeme, oda duvarı, merdiven ve yıkım voxel oyun kodunda kalır. İsteğe bağlı 16×16 iç mekân dokuları ve daire yerleşim planları bu teslimde üretilmedi. Yeni ses, AI, sürüş fiziği, loot tablosu, recipe veya otomatik oyun entegrasyonu yoktur.
