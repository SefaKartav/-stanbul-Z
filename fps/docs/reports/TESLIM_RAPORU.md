# Teslim raporu — sabit kurgusal şehir, derin üretim, yumuşak grafik (29–30 Eylül 2026)

Görev: `docs/CLAUDE_CODE_YENI_VIZYON_PROMPTU.md`. Kanıt düzeyi: *test* = otomatik test geçiyor, *ölçüm* = oyunda pencerede ölçüldü, *kod* = yazıldı ve bağlı. **Hiçbir madde insan eliyle fare/klavyeyle oynanarak doğrulanmadı**; oyun içi doğrulamalar betikli ekran görüntüsü, ölçüm senaryosu ve sahne testleridir.

**Son durum:** `godot.ps1 tests` → **145 test, 0 başarısız** (başlangıçtaki 122 + 23 yeni: üretim sistemleri, kuyruk, yeni harita, nüfus, kabul). `export.ps1` → `build\fps\IstanbulZ.exe` (142 MB); paketli EXE duman testi yeni dünyayı (Yeni İstanbul, Rıhtım) açtı, 173 FPS.

### Başlangıç kanıtı
| Konu | Bulgu |
|---|---|
| Tarif sayısı N | Content'in yüklediği benzersiz tarif **76** (gunsmith 14, network 1, refining 22, survival 24, survival_food 15) |
| Eski harita | `maltepe_besiktas` 12.390 × 16.090 m kutu (~199 km²), oynanabilir koridor ~42,7 km² |
| Zombi yoğunluğu | kalıcı nüfus yok; oyuncu çevresinde 26 (gürültüyle 150'ye kadar) geçici zombi, gece ×2 |
| Grafik (1080p, gölge orta) | bench: boşta 99, gezinme 89, kalabalık 71 FPS; p99 en kötü 20,8 ms. Sert gölge, AA yok, yüksek frekanslı doku gürültüsü |

### 1. Sabit 100 km² harita — `data/map/yeni_istanbul.json` (dünya sürümü 1)
| Konu | Durum | Kanıt |
|---|---|---|
| Geliştirme aracı `tools/city_design/build_fixed_city.py`: sabit tohum, oyun açılışında üretim YOK; iki ayrı süreçte aynı içerik hash'i | tamam | hash karşılaştırması, `test_yeni_istanbul` |
| 10.000 × 10.000 m, 1 birim = 1 m; su 20,00 km², alanlar (km²): tarihî 11,9 · konut 22,0 · ticaret 9,9 · sanayi 9,9 · kurumsal 14,2 · yeşil 12,2 | tamam | test |
| Kaplama (taban/parsel): tarihî %53,8 · konut %43,1 · ticaret %49,0 · sanayi %33,1 · kampüs %29,8 · yeşil %1,6 (hepsi hedef bantta) | tamam | test |
| 24 özgün semt (Rıhtım, Çarşıbaşı, Kubbealtı, Surdibi, Saraykapı…), boğaz + haliç + güney/doğu kıyısı, yokuşlar (0–43 m), 59.467 bina, 1.600 km yol | tamam | ölçüm (yükleme 2,1 sn) |
| Kurumlar: 3 askerî alan + 8 kontrol noktası, 4 hastane + 8 sağlık ocağı, 24 eczane, 12 okul, 2 hapishane; 8 tarihî odak (kule, kubbe, saray avlusu, sarnıç, sur, han, kıyı konağı, meydan) | tamam | test (sayılar birebir) |
| Her kurum türünde kapıdan GERÇEK oyuncu gövdesiyle girilir, kullanılan tüm katlara merdivenle çıkılır, her container ulaşılır; kuruma özgü container/loot (okul, hapishane, askerî, hastane) | tamam | `test_institutions_enterable_with_themed_loot`, `test_themed_loot_differs` |
| Yeni sınıflar/yerleşimler: school, prison, checkpoint, clinic, hastane servisi, askerî koğuş/cephanelik; iz3_ mobilyalar (`tools/city_design/install_classes.py`) | tamam | içerik doğrulaması |
| Geçitler: asma köprü + boğazda 2 alçak geçit + haliçte 2 geçit + boğazın kuzeyinden kara yolu → alternatifsiz dar boğaz yok | tamam | test |
| Doğuş (Rıhtım İskele Meydanı): çeşme 21 m, eczane 255 m (~2,5 dk yürüyüş), semt keşif noktaları medyan 343 m, büyük hedefler arası medyan 832 m | tamam | rapor/test |
| Dünya sınırı: 40 m kenar bandı girilemez; 70 m kala sınır/açık deniz mesajı (sessiz duvar yok) | tamam | kod + test |
| Görevler yeni POI kimliklerine taşındı (`migrate_quests.py`); eski haritalar `quests/place_roles.json` ile aynı zinciri eski adlarıyla oynar | tamam | test |
| Harita ekranı: kurum katmanı + lejant (Harita Seti varsa hepsi, yoksa 350 m), semt adları, kurgusal lisans notu | tamam | ekran görüntüsü |
| Kayıt: yeni dünya ayrı `map_id`; eski kayıt kendi haritasını açar, değiştirilmez | tamam | mevcut kayıt testleri |

### 2. Yumuşak grafik
| Konu | Durum | Kanıt |
|---|---|---|
| Prosedürel dokular 3×3 yumuşatma (desen korunur, piksel kumu gider), cam parıltısı yumuşak | tamam | önce/sonra aynı kare |
| Mat palet (doygunluk 0,86, kontrast 0,98), uzakta mip yanlılığıyla titremesiz doku, daha yumuşak AO/parlama | tamam | ekran görüntüsü |
| Düşük/Orta/Yüksek ön ayar + ayrı Kenar yumuşatma (Kapalı/FXAA/MSAA 2x/4x), gölge 0–3 (yumuşak filtre, yüksekte PCSS), "Yumuşak görünüm" anahtarı | tamam | Ayarlar > Grafik |
| Aynı makine durumunda arka arkaya A/B (Orta): eski görünüm 44–56 FPS, yumuşak görünüm 48–63 FPS → **ölçülebilir maliyet yok** | ölçüm | `--legacy-look` ile |

### 3. Üretim ve inşa
| Konu | Durum | Kanıt |
|---|---|---|
| **N = 76 → 785 tarif** (709 yeni): yapı 183, işleme 102, alet 62, silah 87, savunma 60, elektrik 55, gıda 86, sağlık 51, depolama 49, araç 50 | tamam | `test_recipe_count_and_families` |
| Her çıktının işlev sınıfı ve çalışan işleyicisi (içerik doğrulaması oyunu açtırmaz) | tamam | test |
| 785 tarifin tamamı gerçek CraftingService yoluyla hata ayıklama envanterinden üretilir | tamam | `test_every_recipe_crafts_from_debug_inventory` |
| 12 istasyon (kademeli kitler), elektrik ağı (jeneratör yakıt/ses, akü, güneş/rüzgâr, direk, şalter, sensör), tarım, toplama aletleri, yapı döngüsü (taslak→yükselt→onar→sök), kapılar | tamam | `test_craft_systems`, `test_build` |
| C ekranı: aile rayı + alt kategori, arama (ertelenmiş), favori/öğrenilmiş/yapılabilir, kilit açılma yolu, kuyruk (8, tek tek iptal), B kipine geçiş, kullanım açıklaması | tamam | ekran görüntüsü |
| Kuyruk: eksik malzemede duraklar, iptal eşya yakmaz/çoğaltmaz, kayıt/yükle | tamam | `test_zz_craft_queue` |
| Kabul 5: jeneratörü besle/kapat → lamba söner, tareti besle, suyu arıt, yemek tüket, araca parça tak, kaydet/yükle | tamam | `test_zz_acceptance` |

### 4. Zombi yoğunluğu — `src/ai/population.gd`, `data/world/zones.json`
| Konu | Durum | Kanıt |
|---|---|---|
| Kalıcı bölgesel nüfus (100 m hücre): medyanlar tarihî 360, ticaret 313, konut 170, sanayi 102, kurumsal 101, yeşil 41 /km²; toplam 15.268 | tamam | `test_population` |
| Kurum nüfusu (hastane 60–120, askerî 70–120, hapishane 60–110, okul 40–70…) kendi karışımıyla; semt bütçesine ikinci kez eklenmez | tamam | test |
| Üç katman: yakın tam AI (≤90, görüş dışında ve ≥35 m'de belirir), orta temsil (≤240, tek MultiMesh), uzak bölgesel sayı; uzaklaşan zombi canıyla temsile döner | tamam | ölçüm |
| Doğuşun 100 m çevresi boş, 100–250 m kademeli; öldürülen hücreden düşer, kayıtta saklanır, günde %5 dolar | tamam | test |
| 7. gece dalgası üssün bölge yoğunluğuna göre ×0,6–1,9 | kod | |

### Performans (RTX 3050 Laptop, 1920×1080, Orta, `yeni_istanbul`)
| Senaryo | FPS | p95 | p99 |
|---|---:|---:|---:|
| Boşta | 197 | 5,6 ms | 6,3 ms |
| İç mekân | 131 | 10,8 ms | 12,6 ms |
| Gezinme | 148 | 11,7 ms | 13,3 ms |
| Duvar kırma | 152 | 12,1 ms | 14,9 ms |
| Araç | 142 | 7,4 ms | 8,1 ms |
| Uzun yol 20 m/sn | 88 | 14,7 ms | 20,5 ms |
| 80 zombi | 85 | 18,5 ms | 27,2 ms |
| Hastane çevresi (32 tam AI + 159 temsil) | 165 | 6,9 ms | 9,2 ms |
| Tarihî merkez (9 tam AI + 137 temsil) | 175 | 6,1 ms | 6,1 ms |

Hedef (60 FPS, p95 ≤22 ms, p99 ≤33 ms) bütün sahnelerde sağlandı. Not: hedef donanım RTX 2050 ile ölçülmedi. Aynı gün arka planda ağır bir uygulama çalışırken bazı koşular %30–40 düşük çıktı; bu yüzden grafik karşılaştırması aynı makine durumunda A/B yapıldı.

### Eksik / sınırlı kalanlar (açıkça)
* Yeni tariflerin çoğu mevcut 600 + iz3_ modellerine **kontrollü eşleme** ile gösterilir; tarif başına özgün GLB yok.
* Sarnıç yer altı değil, taş salon; sur, kule, kubbe ve saray kanatları dolu hacimdir (iç mekân yok).
* Orta mesafe zombi temsilleri animasyonsuz kapsül silüetlerdir (sisle uzakta okunur).
* Yeni harita için ayrı araç yolculuğu/yakıt dengesi oyun testi yapılmadı; araç ve uzun yol yalnızca ölçüldü.
* Eski gerçek İstanbul kayıtları yeni dünyaya taşınmaz (bilinçli); kendi haritasında açılmaya devam eder.

---

# Teslim raporu — gercek olcek, yasanabilir binalar, 600 model (26 Eylul 2026)

Gorev: onceki `CLAUDE_CODE_GELISTIRME_PROMPTU.md` (29 Eylul 2026 tarihinde `_yedek/promptlar_2026-09-29.zip` arsivine alindi). Bu tarihsel rapor yeni vizyon promptunun tamamlandigi anlamina gelmez. Bu rapor yapilani, olculeni ve eksik kalani ayri ayri yazar.
Kanit duzeyi: *test* = otomatik test geciyor, *olcum* = paketlenmemis oyunda pencerede olculdu, *kod* = yazildi ve bagli.
**Hicbir madde insan eliyle fare/klavyeyle oynanarak dogrulanmadi.**

## Baslangic kaniti (degisiklikten once)

| Konu | Bulgu |
|---|---|
| Calisan harita | `data/map/maltepe_besiktas.json`, bicim v2, olcek **0.65** (1 oyun m = 1.54 gercek m), 8042 x 10410 oyun m |
| Dogus | Kadikoy carsi (40.9910, 29.0250) |
| Hiz | yuru 4.3 m/sn, kos 6.8 m/sn (sikistirilmis haritada ~6.6 / 10.5 gercek m/sn) |
| Arac yakiti | `fuel_per_km x 6` oyun km'si uzerinden |
| Katlar | girilebilir en fazla 2 kat; ust katlar dolu, 3 m ritim; girilebilir katlar 4 m |
| Yedek | `_yedek/fps_600_oncesi_2026-09-25_2131.zip` (kaynak, veri, testler, kullanici kayitlari) |
| Kullanici kayitlari | `saves_fps/autosave` ve `quicksave`: v2, uretici 2, 2. gun, us yok, 52 arac |

## Yapilanlar

| Alan | Durum | Kanit |
|---|---|---|
| OSM cikarici v2: geometrik kesisim, multipolygon/relation, ic avlu, building:part, etiketler, kaynak SHA-256 | tamam | ornek dosya + tam calisma (1276 sn) |
| 1:1 harita (olcek 1.0), tek donusum (`tools/geo.py` = `src/core/geo_transform.gd`, WGS84 derece uzunlugu) | tamam | `harita_raporu.md` |
| Bina yuksekligi kaynagi (`height_source`, `height_conf`), komsu medyani, catisma raporu | tamam | rapor |
| Koridor siniri binalari/sokaklari kesmez (233 ha genisletme) | tamam | test (erisilemeyen dolap 0) |
| Dinamik dikey sinir (96 m tavani kalkti, sutun basina gokyuzu siniri) | tamam | 21 katli bina catiya kadar yurundu |
| Butun katlar 4 m ritim, butun katlara merdiven: U (donuslu), spiral, L, duz, dar binada tirmanma merdiveni; cati cikisi + korkuluk | tamam | `test_multifloor` (33 bina) |
| Buyuk katta ortak koridor, ikinci daire; karma kullanim (zemin dukkan, ust kat konut) | tamam | oda alanlari raporda |
| Kisisel aclik/susuzluk (oyun saatine bagli), esikler, uyarili can kaybi, zorluk, dirilme politikasi, hastalik | tamam | `test_survival` |
| Su: cesme/sadirvan/el pompasi (213 nokta, OSM + cami + park), kirli su, tablet, kaynatma, filtre, yagmur varili | tamam | test + kod |
| Pisirme, bozulma (dunya saati, kayitta korunur), soguk oda (yakitla) | tamam | test |
| Gorev omurgasi: 5 asama, 24 ana adim, 12 yan gorev; durum makinesi, gunluk (J), harita isaretleri, savunma dalgalari, kayip esya yedegi, olen kisiye alternatif | tamam | `test_zz_quests` |
| 50 seviye, 6 dal x 8 = 48 dugum, 19 yeni eylem/tarif/erisim, ustalik sayaclari, puan iadesi, eski rutbe gocu | tamam | `test_progression` |
| Loot: kat basina butce (kullanim x alan x kat x semt, azalan artis), kilitli kasa/silah dolabi (maymuncuk + beceri), yeni gida tablolari | tamam | `test_containers` |
| XP somuru korumasi: yenilenen dolap deneyim vermez, ayni tarif tekrari doyar, ilk semt kesfi | tamam | test |
| 600 model: genisleme manifesti + etkilesim metadatasi okunur, cakisma kontrolu; 128 px ikonlar envanterde | tamam | icerik dogrulamasi |
| Kayit gocu 0.65 -> 1:1 (cografi), kaynak dosya yedegi, rapor | tamam | kullanicinin gercek kaydi ile test |
| Hareket dengesi: yuru 1.7 / kos 3.6 / depar 5.6 m/sn, zombiler x0.82 | tamam | kod |
| Yakit gercek km (gercek km basina eski denge) | tamam | kod |
| Yol gorunumu 1. adim: asfalt/kaldirimda blok basi ton farki bastirildi, paket dokulari | tamam | kod |
| Yol gorunumu 2. adim (OSM orta hattindan yol yuzeyi mesh'i) | **ertelendi** | asagida |

## Olcumler

### Harita (kaynak: `harita_raporu.md`)

| Olcu | Deger | Hedef |
|---|---:|---:|
| Kapsamdaki kaynak bina / ciktida | 25 801 / 25 725 kabul, 0 eksik | 0 eksik |
| Elenen | 13 (6 m2 alti) + gerekceli | gerekceli |
| 250 m hucre alan farki (en kotu) | %0.3 | — |
| Mesafe ciftleri hata (6 cift, en kotu) | %0.18 | <= %1 |
| Kadikoy iskele -> Bostanci sahil, kus ucusu | 7 058 m (oyunda 7 067 m) | — |
| Ayni rota, yurunen yol / surulen yol | 7 632 / 7 765 m, oyunda %0.10 fark | <= %2 |
| Kopru tabliyesi | 1 555 m (gercek ~1 560 m) | — |

Kadikoy -> Bostanci: kosarak ~35 dk, yuruyerek ~75 dk (eskiden ~10 dk).

### Ic mekan (kaynak: `ic_mekan_raporu.md`, gercek govde 0.6 x 1.8 m)

33 gercek bina (2, 3-4, 5-7, 8-11, 12+ katli, avlulu, karma, dar, duzensiz): **32'sinde butun katlar ve cati yurundu**,
baslangicta erisilemeyen container **0**, basamaklarda bas boslugu en az **2.25 m** (hedef >= 2.05). 19 ve 21 katli binalar
catiya kadar yurundu. Kalan 1 bina (15 katli, w1098526372): ayak izi baska bir kayitla cakistigi icin ic plan uretilemiyor;
dolu bina olarak kalir ve raporda listelenir.

### Performans (RTX 3050 Laptop, 1600x900 pencere, gorus 7 chunk, `--script=bench`; RTX 2050 olculmedi)

| Evre | Onceki (0.65 harita) FPS / p99 | Simdi FPS / p99 / en kotu |
|---|---:|---:|
| Bosta | 160 / 11-12 ms | 133 / 11.9 / 14 ms |
| Ic mekan | 127-144 / 9-12 ms | 122 / 13.3 / 17 ms |
| Gezinme | 137-141 / 14 ms | 106 / 14.7 / 19 ms |
| 240 atis | 133 / 13 ms | 122 / 15.1 / 40 ms |
| Arac | 137 / 14 ms | 137 / 7.5 / 9 ms |
| Uzun yol 20 m/sn | 139 / 12 ms | 96 / 17.5 / 30 ms |
| 80 zombi | 75-82 / 27-31 ms | 90 / 15.1 / 18 ms |

Koşudan koşuya ±%20 oynuyor. RAM ~440-560 MB, VRAM ~490 MB. Butun katlarin ici bos ve dosenmis oldugu icin ilkel sayisi
arttı; bunu dengelemek icin: uzak chunk'ta ic yuzeyler meshlenmez (48 m), mobilya yalnizca oyuncunun kat bandinda kurulur,
ic plan arka planda hesaplanir, tur basina en fazla 40 model. Bu duzeltmelerden once uzun yolda tek kare 141 ms idi.

## Eski kayitlar

Kullanicinin iki kaydi (v2, 0.65) acilir: konum cografi olarak ayni yerde (test: 0.6 m sapma), envanter, zaman, ilerleme,
araclar tasinir. **Tasinamayan ve raporlanan:** degismis/kirilmis bloklar (yeni izgarada ayni binaya denk gelmez; kullanicinin
kaydinda 16-18 hucre), sahadaki zombiler (yeniden dogar), dolap icerikleri (yerine aranmis bina orani: ayni oranda dolap bos gelir).
Kaynak dosya `<yuva>_olcek065_yedek.izfps` olarak korunur. Eski beceri rutbeleri puan olarak iade edilir.

## Kalan eksikler ve bilinen sinirlar

- **Ince duvar yok.** Ic duvarlar hala 1 m voxel; prompt 0.10-0.20 m istiyor. Alt-hucre carpisma ve meshleme motor
  degisikligi gerektiriyor; bu turda yapilmadi. Oda olculeri (1 hucre = 1 m2) duvar kalinligini icermez.
- **Kat yuksekligi 4 m** (1 m doseme + 3 m net tavan). OSM kat sayisi korunur ama binalar gercekten ~%30 uzun gorunur.
- **Yol yuzeyi mesh'i** (OSM orta hattindan, capraz sokakta duzgun kenar) ertelendi: yikim/mermi tutarliligi ayri
  geometri gerektiriyor. Yapilan: ton farki bastirildi, paket asfalt/kaldirim dokulari.
- **Zombiler ust katlara cikmaz** (yol bulma sutun basina tek zemin). Merdivenden kacmak guvenli bir taktik.
- Merdivenler 0.5 m x 1 m voxel basamak (prompttaki 0.16-0.20 m basamak gorsel olarak yok).
- Kopru tabliyesi 30 m'de (gercekte ~64 m); rampa egimi arac icin boyle tutuldu.
- Arazi yuksekligi tahmin (OSM'de DEM yok).
- Gorev savunma dalgalari ve denge rakamlari oynanarak ayarlanmadi; tempo tablosu yalnizca simulasyon
  (`test_progression`: 30 saatte ~34. seviye, 45 saatte ~40).
- Paketteki merdiven/duvar GLB'leri (vertical_access, interior_structure) sahnede kullanilmiyor: fiziksel gercek voxel,
  GLB ust uste binerdi. Kullanilan yeni modeller: su/yiyecek istasyonlari, cesme/pompa, 15 meslek karakteri, 7 zombi tipi,
  gorev nesneleri, yeni esyalar, semt kimligi nesneleri (meydan/iskele/park), ozel ic mekan ekipmani ve 600 ikon.
  600 kimligin 227'si veride/kodda kullaniliyor; kalan 373'u (cephe, cati, yol parcasi, merdiven, duvar modulleri,
  arac parcalari) sahnede yok. Tam liste: `asset_kullanim.md`.
- Paket: `build/fps/IstanbulZ.exe` (122.6 MB) disa aktarildi, duman testi gecti, masaustu kisayolu guncellendi.
  118 otomatik test geciyor.
