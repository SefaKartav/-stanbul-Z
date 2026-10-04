# Mimari kararlar

## Guncel kararlar (26 Eylul 2026) -- asagidaki eski bolumlerden onceliklidir

- **Olcek 1:1.** `tools/geo.py` ve `src/core/geo_transform.gd` tek donusumdur (WGS84 derece uzunluklari, surum 2);
  harita JSON'u `transform` alanini tasir. Eski 0.65 haritalarin parametreleri `data/map/legacy_transforms.json`.
  Kayit gocu `src/save/save_migration.gd`: cografi tasima, blok farklari raporlanir, kaynak dosya yedeklenir.
- **OSM cikarici v2** alan birlestirme (multipolygon, ic avlu), building:part, geometrik kesisim, kaynak SHA-256.
  Koridor siniri bina ve sokaklari kesmez. Dogrulama: `docs/reports/harita_raporu.md`.
- **Katlar:** butun katlar 4 m (1 m doseme + 3 m net). `InteriorPlanner` once giris -> merdiven cekirdegi baglantisini
  cozer (U 2x5, spiral 3x3, L, duz, tirmanma merdiveni). Basamaklar ince tabladir; ust kattaki ayni hucrede en az
  2.5 m bas boslugu. Ust katlar en fazla 3 plan varyantini kullanir; karma kullanimda ust kat konut. Kat basina `use`.
- **Dinamik dikey sinir:** sutun basina uretilen en yuksek chunk (`CityGenerator.max_chunk_y`); ustu kesin havadir
  (`VoxelWorld.is_sky`), altinda "bilinmeyen = duvar" kurali gecerli.
- **Performans onlemleri:** uzak chunk (48 m+) ic yuzeyleri meshlenmez (`interior_only` malzemeler, lod 1);
  mobilya yalnizca oyuncunun kat bandinda kurulur; ic plan arka planda; tur basina en fazla 40 model.
- **Kisisel ihtiyaclar** `PlayerVitals` + `Survival` (oyun saatine bagli; `data/world/nutrition.json`).
- **Gorevler** `QuestSystem` (`data/quests/quests.json`), **beceri agaci** `SkillTree` (`data/skills/skill_tree.json`),
  dunya nesneleri `WorldProps` (cesme, sadirvan, gorev nesneleri, semt kimligi).
- **Bilinen sinirlar:** ic duvarlar 1 m (ince duvar yok), zombiler ust katlara cikmaz, yol yuzeyi mesh'i ertelendi.
## Motor: Godot 4.7.2 (kullanıcı kararı, 23 Eylül 2026)

Belge Godot 4'ü önerdi; kullanıcı, önceki "Godot'a geçme" kararını gerçek 3D FPS için değiştirdi. Python sürümünden **taşınan** şeyler davranış ve veridir. Python sınıfları GDScript'te yeniden yazıldı ve eski testlerin karşılıkları GDScript testlerine çevrildi. JSON içerik değiştirilmeden kopyalandı; bilinçli eklemeler şunlar: blok malzemeleri, inşa kataloğu, başlangıç kiti, eşya-model eşlemesi ve El Telsizi.

Native eklenti ya da hazır voxel motoru kullanılmadı. Önce saf GDScript ölçüldü; darboğaz görülürse yalnızca o parça (meshleme ya da AI) C#/GDExtension'a taşınabilir.

## Voxel: tek doğruluk kaynağı

- `VoxelWorld` her hücrede **1 bayt** malzeme indeksi tutar (16³ chunk = 4 KB). Mesh, çarpışma, mermi, görüş ve yol bulma **aynı veriyi** okur. Godot fizik collider'ı kullanılmaz (`VoxelBody` eksen eksen AABB kırpması yapar). Bu yüzden "görünmez duvar" ya da "içinden geçilen blok" yapısal olarak oluşamaz.
- **Farklar kaydedilir:** üretilmiş dünya kayda yazılmaz; yalnızca değişen hücreler, oyuncu kökeni ve hasarlı hücrelerin kalan HP'si yazılır. Chunk boşaltılıp yeniden üretilince farklar uygulanır.
- **Bilinmeyen = duvar:** yüklenmemiş chunk, harita sınırı ve koridor dışı `BOUNDARY` döner. Mermi geçmez, oyuncu düşmez.
- **İş parçacığı:** üretim ve meshleme `WorkerThreadPool`'da, kopya girdiyle çalışır. Mesh sonucu, iş başladığındaki chunk sürümü hâlâ geçerliyse uygulanır; değilse atılır. Ölçümde 240 atışta 14 sonuç atıldı.
- **Görsel:** yüz ayıklama + köşe AO + blok başı ton, `Texture2DArray` (mipmap sızıntısı yok), 4 kademe çatlak, opak ve saydam yüzey ayrı. Greedy birleştirme bilerek yapılmadı (AO ve blok başı veri taşınamazdı); ölçüm gerektirmedi.

## Büyük harita: Maltepe–Beşiktaş koridoru

Belgenin istediği "Maltepe–Bostancı–Kadıköy–Üsküdar + köprü + Beşiktaş" bir dikdörtgen olarak alınsaydı 8×10 km'lik oyun alanı ve 84 milyon sütun ederdi; çoğu Ataşehir gibi kapsam dışı iç bölge. Harita bu yüzden kıyı boyunca çizilen bir **omurga** etrafında 1,1 km genişliğinde bir koridordur.

- **Biçim v2** (`tools/build_corridor.py` → `data/map/maltepe_besiktas.json`, 9,3 MB): kara maskesi 2 m'de satır RLE (oyunda ikili aramayla okunur), arazi 4 m ızgara (çift doğrusal okunur, teras oluşmaz), bina tabanları önceden hesaplı. Ham JSON dizileri hazırlıktan sonra bırakılır (RAM 394 → 299 MB).
- **Kara/deniz:** kıyı çizgisi bariyer, OSM kuralı (kara solda, deniz sağda) ile her kıyı parçasının sağına tohum; her tohum kendi bağlı bölgesini etiketler, **en az 5 tohumun oyladığı ve bilinen kara noktası içermeyen** bölgeler denizdir. Elle seçilen tek tohum karaya düşünce bütün kara "deniz" oluyordu (%97 hatası); oylama bunu yapısal olarak engeller.
- **Sınır:** `VoxelWorld.set_limit` koridor dışı sütunlar için fizik, mermi ve yol bulmaya `BOUNDARY` döner (görünmez duvar). Meshleme `get_visual_block` ile gerçek veriyi okur; koridorun 150 m dışına kadar binalar üretilir, sınır "bıçakla kesilmiş" görünmez, sise karışır.
- **Bellek:** sütun önbelleği iki nesillidir (90 bin + 90 bin); 10 km gezen oyuncuda sınırsız büyümez.
- **Harita ekranı:** 84 milyon sütun oyunda çizilemez; görüntü araçta 4 m/piksel PNG olarak hazırlanır ve JSON'a gömülür.

## 15 Temmuz Şehitler Köprüsü

İki yön yolunun orta hattından tek tabliye (1007 m, ana açıklık 669 m). **Voxel olan:** tabliye (30 m'de, karadan doğrusal rampa, alçak rampanın altı dolgu, yükseği ayaklı; deniz üstünde ayak yok), orta refüj, şerit çizgisi, 2 m korkuluk, çelik kuleler ve kirişler. Bunlar vurulur, delinir, onarılır; zombiler tabliyede yürür (`ground_height` tabliyeyi döndürür).

**Voxel olmayan (`BridgeDecor`):** ana halat, askılar ve uzak siluet. 0,5 m'lik halat 1 m küplerle çizilince merdiven gibi basamaklanıp kırık kafes görünüyordu; halatlar korkuluğun dışında kaldığı için yürüme ve yıkım kuralını etkilemez. Voxel dünya yalnızca görüş yarıçapı kadar üretilir; köprü şehrin simgesi olduğu için yarıçapın ötesinde **sisten etkilenmeyen**, rengi sis rengine yakın (hava perspektifi) sade bir siluet çizilir. Köprü 30 m'lik parçalara bölünür; her parçanın yakın ve uzak hali Godot görünürlük aralığıyla birbirine devredilir.

**Bilinen sınırlama:** yol bulma sütun başına tek zemin tutar; köprünün karadaki yüksek kısmının **altında** (tabliye 4 m'den yüksekken) zombi yol bulamaz, tabliyenin üstünde bulur.

## Ölçek

1 blok = 1 m; oyuncu 1.8 m, göz 1.62 m. Harita sıkıştırılmış: koridor ve Kadıköy **ölçek 0.65** (1 oyun metresi = 1.54 gerçek metre). **Yol genişlikleri ölçeklenmez** (ara sokak 7 m + 1.5 m kaldırım, cadde 10–12 m); bina yükseklikleri de ölçeklenmez (kat × 3 m). Oran harita dosyasına yazılır (`scale`, `center`).

Eski JSON birimleri (16 px = 1 m) `Units` sınıfında çevrilir. Hareket 1/16; algı (görüş/duyma/gürültü) ×2; silah menzili ×3. Aynı katsayı üçüne birden uygulandığı için "hangi ses hangi zombiye ulaşır" oranı korunur.

Arazi eğimi OSM'de olmadığı için **tahmindir** (kıyıdan uzaklık); 0.5 m adımlı yarım bloklarla yürünür, hiçbir yolda tam blokluk basamak oluşmaz. Tahmini kat sayıları haritada `est: true`.

## Girilebilir binalar (23 Eylül 2026, üretici sürümü 2)

> Eski karar ("tasarlanmış oda yok, bina dolu hacim, dışarıdan arama") **geçersizdir**. Aşağıdaki bölüm mevcut uygulamayı anlatır. Sonraki geliştirme gereksinimleri [güncel Claude Code promptundadır](../../docs/CLAUDE_CODE_YENI_VIZYON_PROMPTU.md); promptun yazılmış olması bu gereksinimlerin uygulandığı anlamına gelmez.

**Fiziksel gerçek voxel'dir.** `InteriorPlanner` her bina için deterministik bir plan üretir (tohum: bina kimliği; aynı bina her oyunda aynı): giriş, BSP ile odalar, Kruskal ile kapı açıklıkları, merdiven şeridi, mobilya yerleşimi. `CityGenerator` bu planı chunk üretirken voxel'e çevirir: iç duvar sıva, zemin parke/fayans, merdiven basamağı. Mobilya ve kapılar **gizli katı malzemelerdir** (`"render": "none"`): mesh'e girmez ama çarpışma, mermi, görüş ve zombi yol bulması onları okur. GLB modelleri yalnızca görseldir ve `InteriorView` oyuncunun 42 m yakınında kurar (tur başına en fazla 2 bina, en yakından; mobilya 24 m, kapı 45 m görünürlük mesafesi). Işınlanma yok: iç mekân aynı dünyadır.

- **Hangi binalar:** konut, metruk, market, eczane, elektronikçi, atölye/garaj/sanayi, karakol/askeri, sağlık, kamu (9 yerleşim, 68 mobilya türü). İç alanı 6 m²'nin altında kalan ayak izleri ve girişi sokağa açılamayan binalar dolu kalır (Kadıköy: 594 adaydan 396'sı girilebilir).
- **Giriş doğrulaması:** kapının önü gerçek yürünebilir zemin (yol/kaldırım/avlu; bina, köprü, ağaç gövdesi değil), dış yüzey farkı ≤ 0,55 m. Dış zemin iç zeminden yüksekse kapı 3 blok yapılır (lento çarpmasın). Testler kapıdan girip her container'ın önüne **gerçek oyuncu gövdesiyle (0,6 × 1,8 m)** yürür.
- **Katlar:** zemin kat + merdivenle 1. kat (daire, karakol, sağlık, kamu; 8 yarım basamak, 4 m kat). Üst katlar dolu hacimdir ve **loot içermez** (ulaşılamayan katta loot yok kuralı). Merdiven sığmazsa bina tek katlı planlanır.
- **Kapılar:** aç/kapa hücreleri hava ↔ kapı malzemesi yapar; çarpışma, mermi, görüş ve zombi rotası aynı anda değişir. İçinde gövde varken kapanmaz. Kapalı kapı silahla kırılır → "kırık" (kaydedilir, bir daha kapanmaz). Kapıların %30'u açık başlar. Zombiler açık kapıdan takip eder; bina içinde **doğmaz**.
- **Alternatif giriş:** duvar voxel'dir; vurup delik açmak kapısız giriştir.
- **Işık:** mobilya başına ışık yok; iç mekân ortam ışığı + fener. Mobilyalar gölge düşürmez.

**Bilinen sınırlamalar:** destek fiziği ve zincirleme çökme **yoktur** (altı kırılan yapı havada kalabilir). Yol bulma sütun başına tek zemin tuttuğu için zombiler yalnızca **zemin katı** dolaşır; merdivenden üst kata çıkmazlar.

## Mobilya başına loot (`ContainerRegistry`)

- Kimlik `<bina>:f<kat>:s<yuva>` — plan deterministik olduğu için kayıttan kayda sabit. İçerik **ilk açılışta bir kez** zarla belirlenir (tohum: kimlik), kaydedilir; kaydet/yükle ile yeniden zar atılmaz.
- Tablo = yapı işlevi + oda + mobilya türü (28 tür). "Temel" türler (mutfak dolabı, ecza dolabı…) ilk açılışta ana havuzdan gelir: temel ihtiyaç salt şansa kalmaz. Buzdolabında taze yiyecek yok (konserve, su).
- **Arama:** E yalnızca bakılan, 2,6 m içindeki, önü açık ve oyuncuyla aynı bina/katta olan mobilyayı hedefler. Süreli ve gürültülüdür; hareket/hasar/E kesintisinde eşya verilmez, ilerleme saklanır. Bitince loot paneli açılır: tek / yığın / hepsi (R), kalan kapasite gösterilir, sığmayan içeride kalır.
- **Yenilenme:** bina başına bütçe (`class_budget`), 6 günde bir jeton, en fazla 2; kısmi (%50). Container sayısıyla çarpılmaz. Değerler `data/world/containers.json`'da.
- **Tahrip:** mobilya silahla kırılınca kalan içeriğin %60'ı **bir kez** enkaz yığını olur.
- Cepheden/ayak izinden toplu bina araması ve kalıntı noktası **kaldırıldı**.

## Araç sürüşü

Paketin `vehicle_compatibility.json`'ı ile sürücü koltuğunda dolu model gizlenir; `*_shell_open` + `*_cabin` kurulur. Göz, kabin GLB'sindeki `driver_eye` düğümünden; FOV kabinin `horizontal_fov_degrees` değerinden (sedan 82° yatay) en-boy oranına göre çevrilir. Fare **direksiyonu çevirmez**: bakış aracın burnuna göre ±110° serbest, H ortalar, fare 2,5 sn oynamazsa hızlanırken yavaşça yola döner.

Fizik: kademeli gaz/fren; ileri giderken S fren, durunca geri vites. Direksiyon hıza bağlı ve kendiliğinden toparlanır. Çarpışma, modelin gerçek boy/eniyle (manifest `dimensions_m`) yönlendirilmiş dikdörtgendir; taban 0,5 m aralıkla voxel sütunlarında örneklenir, hareket ≤ 0,25 m alt adımlara bölünür (tünelleme yok). Basamak toleransı 0,55 m: bordura ve 0,5 m'lik eğim adımlarına çıkılır, 1 m duvara/barikata **çıkılmaz**. Araçlar birbirine ayrık eksen testiyle çarpar. Yüklenmemiş chunk boşluk sayılmaz: araç önce yavaşlar, sınırda hasarsız durur; akış hız yönünde önden yüklenir. 2 m/sn üstünde inilmez. Araç blok kırmaz.

## Üretim ekranı

Sol liste / sağ ayrıntı; seçim ve kaydırma korunur. Türkçe arama (İ/ı, ş, ğ… katlanır) ve kategori adları. Her eksik gereksinim ayrı satır; adet yazılır, +/−, "en fazla" (alternatif malzemede **çift sayım yok**: rezervasyonlu denetim). Hangi alternatifin harcanacağı gösterilir. "Nerede bulunur?" gerçek loot verisinden (`LootSources`). Alt tarife git + geri. Kaynak (çanta / üs deposu) görünür, sessizce değişmez. Süreli üretim: ilerleme, kalan, iptal, tamamlandı; tamamlanırken yeniden denetlenir (atomik).

## Ekonomi korumaları

- Oyuncunun koyduğu blok `ORIGIN_PLACED`: kırılınca kurtarma düşüşü vermez.
- Crafting, inşa ödemesi, hasat, iş emri ve depo aktarımı **kopyada dene → tek adımda uygula**. Yer yoksa hiçbir şey harcanmaz ve hiçbir şey kaybolmaz.
- Aramada sığmayan eşya silinmez, yerde sonlu yığın olarak kalır.
- Sökülen yapı aynı kalitede iade edilir. Tükenen tuzak iade edilmez.
- Suya en fazla 2 blok çıkma; gerçek köprü tabliyesi destek sayılır (onarım mümkün).

## Kayıt

`user://` = `%APPDATA%\IstanbulZ` (eski oyunla aynı kök). FPS kayıtları `saves_fps/` altında, ZSTD sıkıştırılmış JSON. Yazma atomik (`.tmp` → doğrula → `.bak` → yerine koy). Harita kimliği ve üretici sürümü uyuşmayan kayıt açılmaz, dosyası korunur; tek istisna tanımlı göçtür: **kayıt v1 → v2** (üretici 1 → 2). Eski bina arama hakları container'lara çevrilir (tam aranmış binanın dolapları boş gelir, ikinci kez ödül yok), yenilenme saati eski son arama gününden başlar, dünya farkları (kırılan/konan bloklar) aynen uygulanır, oyuncu duvar/mobilya içindeyse en yakın boş yere alınır. Göç gerçek bir v1 kaydıyla test edilir (`tests/fixtures/eski_v1_*.izfps`). Yükleme hatasında otomatik kayıt o oturumda yazmaz. Eski 2D kayıtlar (`saves/`) okunur ve listelenir ama aktarılmaz: koordinatlar ve harita uyumsuz.
