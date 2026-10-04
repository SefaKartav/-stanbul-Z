# Istanbul-Z — voxel FPS

Birinci şahıs, voxel görünümlü zombi hayatta kalma ve koloni oyunu. Yeni oyunlar **Yeni İstanbul**'da geçer: İstanbul'un tarihî dokusunu taşıyan, birebir kopya olmayan, **sabit** 10 × 10 km (100 km²) kurgusal şehir — boğaz, haliç, tarihî yarımada, 24 semt, 59 bin bina. Her bina ve her blok silahla parçalanabilir. Eski gerçek İstanbul haritaları (Maltepe–Beşiktaş koridoru, Kadıköy) eski kayıtlar için korunur.

**Motor:** Godot 4.7.2-stable (GDScript) · **Eski haritaların verisi:** © OpenStreetMap katkıcıları, ODbL

> **30 Eylül 2026 — sabit kurgusal şehir, derin üretim, yumuşak grafik** (ayrıntı ve ölçümler: [docs/reports/TESLIM_RAPORU.md](docs/reports/TESLIM_RAPORU.md)).
> - **Yeni İstanbul** (`data/map/yeni_istanbul.json`, dünya sürümü 1): su 20 km², tarihî 12 · konut 22 · ticaret 10 · sanayi 10 · yeşil 12 · kurumsal 14 km². 3 askerî alan + 8 kontrol noktası, 4 hastane + 8 sağlık ocağı, 24 eczane, 12 okul, 2 hapishane, 8 tarihî odak; her kurumun kendi loot'u ve zombi karışımı. Asma köprü + alçak geçitler + kara yolu. Doğuş: Rıhtım İskele Meydanı. Harita açılışta üretilmez; geliştirme aracıyla bir kez üretilip dosyada sabittir.
> - **785 tarif** (önce 76), 10 aile, 12 istasyon; her çıktı gerçek bir işleve bağlı (kuşan, yerleştir, tüket, araca tak…). Elektrik ağı, tarım, toplama aletleri, yapı yükseltme/onarım/söküm, kapılar, üretim kuyruğu.
> - **Kalıcı zombi nüfusu:** merkez ~250–450, konut ~120–220, çeper ~20–60 /km²; öldürdüğün zombi geri doğmaz (günde %5 dolar). Doğuşun 100 m çevresi güvenli.
> - **Yumuşak grafik:** mat palet, yumuşatılmış dokular, yumuşak gölge; Ayarlar > Grafik: Düşük/Orta/Yüksek, kenar yumuşatma, "Yumuşak görünüm".
> - **Harita (M):** kurum katmanı ve lejant; tüm kurumları görmek için çantada **Harita Seti** taşı.
> - **Ses paketi** (`fps/assets/audio/`, 99 WAV, 44.1 kHz): `python fps/tools/audio/make_sfx.py` ile üretilir (katmanlı silah sesi + sokak yankısı, formant sentezli zombi sesleri, malzemeye göre darbe/adım, kovan düşüşü). Her ses için birden çok varyant (`<kimlik>_1.wav`, `_2.wav`…) rastgele çalınır. Kendi kaydın ya da CC0 bir sesi aynı adla klasöre koyarsan kod değişmeden onu kullanır.

> **26 Eylul 2026 guncellemesi** -- ayrinti ve olcumler: [docs/reports/TESLIM_RAPORU.md](docs/reports/TESLIM_RAPORU.md).
> Harita artik **1:1** (1 birim = 1 gercek m; Kadikoy -> Bostanci yolu ~7.6 km, kosarak ~35 dk). Butun binalarin
> **butun katlarina** merdivenle (U, spiral; dar binada tirmanma merdiveni) cikilir, duz catilara cikis vardir.
> Kisisel **aclik ve susuzluk** (HUD'da Tokluk/Su), cesme/sadirvan/el pompasindan kirli su, kaynatma/tablet/filtre,
> pisirme ve bozulma. **Gorev omurgasi** (J): 24 ana adim + 12 yan gorev. **Beceri agaci** (K): 50 seviye, 6 dal x 8 dugum.
> 600 modellik paketin yeni 300 modeli okunur (karakterler, zombi tipleri, su/yiyecek istasyonlari, gorev nesneleri, ikonlar).
> Bu paragrafin altindaki bolumlerde eski 0.65 olcegine ait sayilar gecmis olcumlerdir.

> **29 Eylül 2026 — arayüz ve yeni asset paketi.**
> - **Yazı tipi:** Barlow (gövde, sayılar) + Barlow Condensed (başlıklar, HUD etiketleri), `fps/assets/fonts/`, SIL OFL 1.1, Türkçe karakterler tam. Tüm renk, yazı ve kontrol stilleri tek yerde: `src/ui/ui_theme.gd` (tip varyasyonları: `PrimaryButton`, `MenuItem`, `RailButton`, `Card`, `Inset`). Arayüz dokuları artık doğrusal filtreli (yazı pürüzü giderildi).
> - **Yeniden tasarlanan ekranlar:** ana menü, ortak ekran çerçevesi (başlık, tuş ipuçları, alt bilgi), üretim (kategori rayı + ikonlu liste + ayrıntı kartı + gereksinim kartları), envanter (istatistik şeridi + ayrıntı kartı), duraklatma/ayarlar ve HUD (kartlı yaşam göstergeleri, hasar izi, ikonlu yuvalar, tuş kapağı ipuçları). Diğer ekranlar temayı otomatik alır.
> - **Yeni paket:** `fps/assets/istanbul_z_soft_expansion/` (360 `iz3_` model + ikon + metadata). `AssetLibrary` ek paketleri kendi kökünden okur; eski 600 kimlik ezilmez, `replaces_asset_id` yalnızca görseli değiştirir. Kökteki `Istanbul-Z_600_Model_Asset_Paketi_soft_expansion/` klasörü oyun tarafından **okunmaz** (kaynak kopya).
> - **Bilinen eksik:** eski (elle yazılmış) veri dosyalarındaki bazı eşya adları hâlâ Türkçe karaktersiz ("Fisek", "Kirikkale"); 30 Eylül'de üretilen 700 eşya/tarif Türkçe karakterlidir.

## Çalıştırma

| Ne | Komut |
|---|---|
| Oyunu aç (paketlenmiş) | Masaüstündeki **Istanbul-Z** kısayolu → `build\fps\IstanbulZ.exe` |
| Paketle + test + kısayol | `powershell -ExecutionPolicy Bypass -File fps\tools\export.ps1` |
| Testler (başsız) | `powershell -ExecutionPolicy Bypass -File fps\tools\godot.ps1 tests` |
| Editörsüz çalıştır | `powershell -ExecutionPolicy Bypass -File fps\tools\godot.ps1 run` |
| Test sahası | `... godot.ps1 run -Extra "-- --site=test"` |
| Küçük Kadıköy haritası | `... godot.ps1 run -Extra "-- --site=kadikoy"` |
| Eski koridor haritası | `... godot.ps1 run -Extra "-- --site=maltepe_besiktas"` |
| Ölçüm senaryosu (yeni harita) | `... godot.ps1 run -Extra "--resolution 1920x1080 -- --site=yeni_istanbul --script=bench --preset=1"` (`--preset=0/1/2` düşük/orta/yüksek, `--aa=0..3`, `--legacy-look` eski görünüm karşılaştırması) |
| Arayüz ekran görüntüsü | `... -- --site=test --screen=craft --shot=C:\tmp\craft.png --shot-delay=3` (`craft`, `inventory`, `pause`, `map`, `colony`, `skills`, `journal`) |
| Ana menü görüntüsü | `... -- --menu-shot=C:\tmp\menu.png` |

Menüyü atlayıp doğrudan oyunu açmak için `--` sonrasında `--site=`, `--shot=` ya da `--load=` verilmelidir (yalnızca `--script=` menüde bekler). Godot editörü `%LOCALAPPDATA%\Programs\Godot\4.7.2\` altında (taşınabilir). Oyun çalışırken Python'a, OSM dosyasına ya da internete bağlı **değildir**.

İçerik ve harita araçları (yalnızca geliştirme; Python 3 + numpy; oyun çalışırken gerekmez):

```
python fps/tools/city_design/build_fixed_city.py     # ~60 sn: Yeni İstanbul (sabit tohum, aynı hash)
python fps/tools/city_design/install_classes.py      # okul/hapishane/kontrol/sağlık sınıfları, yerleşim, container
python fps/tools/city_design/migrate_quests.py       # görev çapaları -> yeni POI kimlikleri (+ eski harita tablosu)
python fps/tools/content_gen/main.py [--check]       # 709 üretilmiş tarif/eşya/yapı (gen_*.json), doğrulama
```

Eski gerçek İstanbul haritalarının yeniden üretimi (`pip install osmium numpy`):

```
python fps/tools/osm_extract.py turkey-260909.osm.pbf     # ~16 dk, bir kez
python fps/tools/build_corridor.py                         # ~26 sn: Maltepe-Beşiktaş koridoru (varsayılan harita)
python fps/tools/build_map.py --id kadikoy --center 40.9903 29.0243 --real-size 470 --scale 0.65 \
       --spawn 40.9910 29.0250 --sea-seed 40.9921 29.0217 --sea-seed 40.9923 29.0220   # küçük test şehri
```

`build_corridor.py` kara/deniz ayrımını elle seçilmiş tohumla değil, OSM kıyı kuralıyla (kara solda, deniz sağda) yerleştirilen yüzlerce tohumun **oylamasıyla** yapar ve sonunda altı bilinen noktayı (Kadıköy, Beşiktaş, Bostancı, Üsküdar kara; Boğaz, Marmara deniz) doğrular.

## Kontroller (hepsi Esc → Tuş atamaları'ndan değiştirilebilir)

| Tuş | İşlev | Tuş | İşlev |
|---|---|---|---|
| WASD | hareket | Shift | koş |
| Space | zıpla | Ctrl | çömel |
| Caps Lock | yürü/koş geçişi (1.7 / 3.6 m/sn) | Shift | depar (5.6 m/sn, nefes) |
| J | görev günlüğü | N / U | hızlı ye / hızlı iç |
| Sol tık | ateş (inşa kipinde: kur) | Sağ tık | nişan |
| R | doldur (inşa: döndür) | 1–4, tekerlek | silah (inşa: seçim) |
| E | kapı aç/kapa, baktığın dolabı ara, al, konuş, araca bin/in | F | fener |
| I, Tab | envanter | C | üretim |
| B | inşa kipi | L | koloni ve üs |
| M | harita | K | beceriler |
| Q / V / G / X / Z | itekleme / kaçınma / ilk yardım / adrenalin / dikkat dağıtma | F5 / F9 | hızlı kaydet / yükle |
| F3 | teşhis (FPS, p95/p99, chunk) | Esc | duraklat, ayarlar |

**Loot paneli** (dolap araması bitince açılır): eşyayı seç → "1 adet al" / "Yığını al" (çift tık da yığın), **R** = sığan her şeyi al. Kalan çanta kapasitesi panelde yazar; sığmayan dolapta kalır. E/Esc kapatır; 3 m'den uzaklaşınca kendiliğinden kapanır.

**Araçta:** W gaz · S fren, durunca geri vites · A/D direksiyon (bırakınca toparlanır) · Space el freni · fare serbest bakış (direksiyonu çevirmez) · **H** bakışı ortala · E in (yalnızca dururken, < 7 km/sa). Gösterge alt ortada: hız, vites (I ileri / N boş / G geri), yakıt, sağlamlık.

**Duraklatma politikası:** Harita ve Esc menüsü dünyayı durdurur. Envanter, üretim, koloni ve beceri ekranları durdurmaz (hayatta kalma baskısı sürer). Hiçbir menüde tıklama ateş etmez.

## Oynanış özeti

- **Yıkım:** her katı blok malzemesine bağlı cana sahip (cam 10, tahta 60, tuğla 150, beton 300, çelik 600). Silah çarpanı HP'den ayrı: tabancayla tahta 3, tuğla 8, beton 20, çelik 52 atış. Blokları yalnızca **ateşli silah** kırar; yakın dövüş sadece düşmana vurur. Kazma yok.
- **Delme:** delmesiz mermi ilk blokta durur. Tüfek tahtayı deler, 1 m betonu delemez. Cam kırılır ve mermi devam eder. Namlu siperin arkasındayken kameranın gördüğü hedef vurulamaz.
- **Binalar (girilebilir):** konut, market, eczane, elektronikçi, atölye, karakol, sağlık ocağı ve kamu binalarına kapıdan girilir; odalar, iç kapılar ve (daire, karakol, sağlık, kamu) merdivenle 1. kat vardır. Kapı E ile açılır/kapanır, silahla kırılabilir; duvarı delmek de giriş yoludur. Işınlanma yok, iç mekân aynı dünyadır.
- **Mobilya başına loot:** her dolap, raf, çekmece, buzdolabı ayrı aranır (baktığın, yakındaki, önü açık mobilya). İçerik ilk açılışta bir kez belirlenir ve kaydedilir; bina işlevi + oda + mobilya türüne göre temalıdır (eczane dolabında ilaç, gardıropta kumaş, takım dolabında hurda/alet). Arama süreli ve gürültülüdür; kesilirse ilerleme saklanır ama eşya verilmez. Bina başına 6 günde bir sınırlı yenilenme. Kırılan mobilyanın içeriği bir kez enkaz yığını olur.
- **Üs:** sokağın uçlarını barikatla kapat, L → "Burada üs kur". Binalara rol ver (depo, yatakhane, revir, atölye, mutfak).
- **Koloni:** şehirde yardım bekleyenleri bul (El Telsizi yön gösterir), E ile ikna et, üsse götür. İş ver; zanaatkâr iş emirlerini depodan harcayarak üretir, nöbetçi gerçek fişek harcar.
- **Ölüm:** üssünde uyanırsın, çantan düştüğün yerde kalır, 48 saat geçer. Üs yoksa oyun biter.
- **Dalga:** her 7. gece büyük dalga üsse yürür; sayaç HUD'da.
- **Harita:** 1,1 km genişliğinde, omurga boyunca ~10 km'lik koridor (ölçek 0,65). Koridorun dışı ufukta görünür ama girilemez (görünmez sınır). Semtlerin zombi karışımı ve ganimet çarpanı farklıdır (Maltepe sakin, Caddebostan zengin ama kalabalık, köprü tehlikeli).
- **15 Temmuz Şehitler Köprüsü:** iki yakayı bağlayan tek kara yolu. Rampa ile 30 m'ye çıkan voxel tabliye (orta refüj, şerit çizgileri, 2 m korkuluk), kıyılarda çelik kuleler; tabliye ve kuleler vurulur, delinir, onarılır. Üstünde terk edilmiş araç sırası vardır. Ana halat ve askılar dekordur; köprü görüş mesafesinin ötesinden sade bir siluet olarak görünür.
- **Araçlar:** sürücü koltuğundan açık kabin görünür (şeffaf cam, direksiyon ve ibreler hareketli). Bordura ve yokuşa çıkar, 1 m duvara/barikata çıkmaz; gerçek boy/enle çarpışır. Yakıtı gerçek eşyadan doldurulur, blok kırmaz, çarpınca hasar alır. Park etmiş araçlar doğuşun çevresinde kümelenir, koridora serpilir ve köprüde durur.
- **Üretim (C):** solda liste, sağda ayrıntı; Türkçe arama, eksikler satır satır, adet yaz/+/−/en fazla, hangi alternatif malzemenin harcanacağı, "Nerede bulunur?" (gerçek loot verisinden), alt tarife git/geri, kaynak (çanta/üs deposu) görünür, süreli üretimde ilerleme ve iptal.

## Durum ve kanıt

Ayrıntı: [docs/TASIMA_TABLOSU.md](docs/TASIMA_TABLOSU.md).

- **Otomatik test:** 99 GDScript testi, ~73 sn. Önceki 70 teste ek olarak:
  - *İç mekân:* plan kapsamı ve determinizmi; kapıdan girip 317 container'ın önüne gerçek gövdeyle (0,6 × 1,8 m) yürüme (0 ulaşılamaz); merdivenle 1. kata çıkma; kapı aç/kapa/kır ile çarpışma + mermi/görüş + zombi rotasının birlikte değişmesi, gövde varken kapanmama.
  - *Loot:* tek seferlik zar ve kayıt döngüsü, kısmi alma ve kapasite, tahripte bir kez enkaz, yenilenme kuralları, bina bütçesi (container sayısıyla çarpılmaz), sabit tohumla tematik dağılım, temel ihtiyaçların şansa kalmaması, hedefleme (görüş hattı + içeride), arama kesilme politikası.
  - *Üretim:* "en fazla N" = gerçekten N kez üretilir, aynı eşya iki girdiye sayılmaz, harcama planı, dolu çantada atomiklik, her girdinin gerçek bir kaynağı olması.
  - *Araç:* çarpma blok kırmaz, gerçek boy/en ile yönlendirilmiş çarpışma, bordur çıkılır / 1 m duvar çıkılmaz, 0,5 m adımlı yokuş, 35 m/sn + 0,1 sn kare ile tünelleme yok, yüklenmemiş chunk'ta hasarsız duruş, açık geri vites, hıza bağlı direksiyon, hızlıyken inilmez, sedan/van/minibüste açık kabuk + kabin + `driver_eye`.
  - *Kayıt:* kullanıcının gerçek v1 kaydı açılır; aranmış binanın dolapları boş, v1'de kırılan/konan bloklar yerinde, oyuncu duvarda değil, yeniden v2 yazılır.
- **Ekran görüntüsü (otomatik, pencerede, 1600×900):** market, eczane ve daire içi (gündüz ve gece, fenerli/fenersiz), loot paneli, üretim ayrıntısı, sedan/van/minibüs sürücü görüşü (ileri ve yana bakış); paketlenmiş EXE'nin duman testi. Önceki: Kadıköy doğuşu, köprü, siluet, harita.
- **Oynanarak doğrulanmadı:** Bu geliştirme ortamında fare/klavye ile oynanamıyor. Kapı/dolap etkileşiminin eldeki hissi, sürüşün fare+klavye ile rahatlığı ve üretim ekranındaki tıklama akışı **insan tarafından** denenmedi.

## Ölçümler

NVIDIA RTX 3050 Laptop, 1600×900 pencere, gölge orta, görüş 7 chunk, `--script=bench`. Evreler: boşta, gezinme (8 m/sn), 240 atış, araç (10 sn gaz), uzun yol akışı (20 m/sn düz), 80 zombi.

**Maltepe–Beşiktaş koridoru** (Kadıköy doğuşu, varsayılan harita):

| Senaryo | Ort. FPS | p95 | p99 | En kötü | Not |
|---|---:|---:|---:|---:|---|
| Boşta | 176 | 7.0 ms | 7.1 ms | 7.1 ms | 540 chunk mesh, 0.51 M ilkel |
| Gezinme (8 m/sn, akış) | 151 | 10.8 ms | 13.0 ms | 16.7 ms | chunk mesh işçide ≤ 42 ms |
| 240 atış, 25 blok yıkımı | 156 | 9.5 ms | 11.9 ms | 27.4 ms | 15 eski mesh sonucu atıldı (sürüm kontrolü) |
| Araç, 10 sn (94 m) | 143 | 12.5 ms | 14.1 ms | 17.8 ms | |
| Uzun yol, 20 m/sn | 127 | 11.8 ms | 16.7 ms | 33.2 ms | en ağır chunk akışı |
| 80 zombi (90 uyanık AI) | 81 | 21.2 ms | 29.2 ms | 46.4 ms | AI GDScript'te |

**İç mekân + mobilya + yeni sürüş sonrası** (aynı makine, aynı ayarlar, aynı senaryo; yeni "iç mekân" evresi: doğuşa en yakın dairenin içinde 6 sn etrafa bakış):

| Senaryo | Önce FPS / p99 | Şimdi FPS / p99 | Not |
|---|---:|---:|---|
| Boşta | 176 / 7.1 ms | 160–163 / 10.8–12.5 ms | iç duvar/döşeme mesh'i (+%14 ilkel), ~300 mobilya+kapı düğümü |
| İç mekân (yeni) | — | 127–144 / 9.4–11.9 ms | dairenin içi |
| Gezinme | 151 / 13.0 ms | 137–141 / 13.5–14.6 ms | bina görseli kurulumu en fazla 2.9 ms |
| 240 atış | 156 / 11.9 ms | 133–134 / 13.0–13.3 ms | |
| Araç, 10 sn | 143 / 14.1 ms | 137 / 13.9–14.1 ms | yeni fizik: yönlendirilmiş taban örneklemesi |
| Uzun yol, 20 m/sn | 127 / 16.7 ms | 139–140 / 12.0–12.3 ms | |
| 80 zombi | 81 / 29.2 ms | 75–82 / 27.0–31.3 ms | |

Aralıklar son iki koşudur; boşta p99 önceki ölçümden belirgin kötü (7 → 11–12 ms), ortalama kare süresi ise 5,7 → 6,1–6,2 ms. İlk sürümde tek binanın görselini kurmak 28 ms sürüyor, çizim çağrısı boşta 722'ye çıkıyordu; üç düzeltme yapıldı: mobilya 24 m / kapı 45 m görünürlük mesafesi, aynı kaynak materyalin örnekler arasında paylaşılması (80 zombide çizim çağrısı 1097 → 640), iç mekân ve kabin modellerinin oyun açılışında arka planda yüklenmesi + tur başına en fazla 2 bina. Kalan maliyet (boşta ~%5–9) iç duvar geometrisinin kendisidir.

Karşılaştırma, küçük Kadıköy haritası aynı oturumda: boşta 174 FPS, 80 zombi 90 FPS / p99 23,8 ms. Kalabalık p99'u koşudan koşuya ±5 ms oynar; önceki bir oturumda Kadıköy'de 15,6 ms ölçülmüştü.

Koridor haritası 0,9 sn'de yüklenir. RAM ~300–450 MB (Kadıköy ~150–175 MB; fark 27 bin binanın ve 47 bin yol segmentinin hazırlanmış kayıtları), VRAM ~460–495 MB. **RTX 2050 hedefi için sonuç iddia edilmez**: o GPU bu makinede yok.

## Klasörler

```
fps/
  data/        JSON içerik (eşya, tarif, silah, loot, zombi, koloni, blok malzemeleri, harita)
  assets/      istanbul_z_v1 (600 model), istanbul_z_soft_expansion (360 iz3_ model), fonts/ (Barlow, OFL), blocks/ ve audio/ (final asset yuvaları)
  src/
    autoload/  content (kayıt defteri + doğrulama), settings (ayar + tuş atamaları)
    voxel/     chunk verisi, mesh'leyici, arazi akışı, ışın, çarpışma, dokular, shader'lar
    world/     şehir üreticisi (OSM, v1/v2 harita), köprü dekoru, araçlar, bina kayıtları, arama, gün/gece, dalga, yerdeki eşya
    player/    FPS denetleyici, silah görünümü, inşa kipi, yetenekler, hayati değerler
    combat/    silah durumu, hitscan, aktör kayıtları, durum etkileri
    ai/        zombi FSM, yönetici, akış alanı
    base/      üs, yerleştirilebilirler, inşa kuralları, koloni, iş emirleri, hayatta kalanlar
    crafting/  tarif, servis, grafik    items/  eşya, yığın, envanter, loot, kullanma
    ui/        HUD, ekranlar (envanter, üretim, koloni, harita, beceri, duraklatma)
    save/      atomik kayıt    game/  sahne bağlayıcı    main/  menü
  tests/       GDScript testleri + koşucu
  tools/       godot.ps1, export.ps1, OSM araçları, simge
  docs/        taşıma tablosu, asset listesi, mimari, temizlik planı
```
