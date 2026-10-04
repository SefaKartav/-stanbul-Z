# Istanbul-Z — Sistem taşıma tablosu (2D pygame → Godot 4 voxel FPS)

Tarih: 23 Eylül 2026 · Motor: Godot 4.7.2-stable, GDScript · Kaynak: `src/istanbulz/` (Python) → `fps/src/`

## Durum sözlüğü

**Eski oyun sütunu** (kaynak kodu okunarak tespit edildi; README'deki sayılar kanıt sayılmadı):

| Etiket | Anlamı |
|---|---|
| çalışıyor | Kod var, oyunda bağlı, testi var |
| kısmen | Kod var ama bir parçası bağlı değil ya da veride kalmış |
| yalnızca hedef | Veri alanı ya da yorum var, oynanış yok |

**FPS sütunu** üç ayrı kanıt düzeyinde yazılır:

| Etiket | Anlamı |
|---|---|
| test | Otomatik GDScript testi geçiyor |
| kod | Kod yazıldı ve derleniyor, oyunda bağlı; otomatik testi yok |
| görsel | Paketlenmiş oyunda ekran görüntüsüyle görüldü |
| oynanarak doğrulanmadı | Hiçbir satır insan eliyle oynanarak doğrulanmadı. Bu ortamda fare/klavye ile oynanamıyor; tüm doğrulama otomatik test ve ekran görüntüsüdür |

## Tablo

| Sistem | Eski kaynak | Eski durum | Korunan davranış | 3D'de yeniden yazılan | FPS durumu | Kabul testi |
|---|---|---|---|---|---|---|
| İçerik kayıt defteri | `content/registry.py`, `schema.py` | çalışıyor | Hata varsa oyun açılmaz; çapraz referans, loot→eşya, bina→tablo, beceri/yetenek çakışması | GDScript `ContentValidator`, `Content` autoload | test | `test_crafting:test_content_loads_without_errors` |
| Crafting çekirdeği | `crafting/recipe.py`, `service.py` | çalışıyor | Tag sorgusu, `min_quality`, tüketilmeyen takım, istasyon+kademe, ağırlıklı kalite, ±6 şans, başarısızlık malzemeyi yer, yan ürün, %55 sökme | Tek işlem güvenliği: ürün sığmazsa hiçbir şey harcanmaz (eskide ürün sessizce kayboluyordu) | test | `test_crafting` (11 test) |
| Crafting grafiği | `crafting/graph.py` | çalışıyor | Ulaşılamaz eşya, boş tag, bilinmeyen çıktı açılışta hata | aynı | test | `test_graph_has_no_unreachable_items` |
| Üretim süresi | `recipes/*.json` `time` | **kısmen**: yalnızca ekranda yazıyordu, üretim anlıktı | Süre verisi | Süre gerçek zamanda işler; malzeme her adet bitince, o anda yeniden denetlenerek harcanır; iptal/yükleme çoğaltmaz | kod | elle: C → Üret |
| Şema açma | `RecipeDef.unlocked` | **yalnızca hedef**: kilitli tarif ve keşif yok | Bayrak | 6 kilitli tarif (susturucu, EMP namlu, otomatik taret, tüfek, SMG, yelek). Şema karakol/askerî/elektronikçi/sanayi aramasında bulunur; oyuncu ve koloni zanaatkârı aynı şema bilgisini paylaşır; kayıtta korunur | test | `test_zz_integration:test_gear_throwables_and_schematics` |
| Üretim ekranı | `ui/screens/crafting.py` | çalışıyor | Eksik malzeme açıklaması, istasyon seviyesi, iş emri | Sol liste/sağ ayrıntı (seçim ve kaydırma korunur), Türkçe arama ve kategori adları, eksikler satır satır, adet yaz/+/−/en fazla (**çift sayım düzeltildi**: aynı eşya iki girdiye sayılmaz), harcanacak alternatif, "Nerede bulunur?" gerçek loot verisinden, alt tarif git/geri, görünür kaynak, süreli üretim ilerleme/kalan/iptal/tamamlandı, atomik tamamlanma | test + görsel | `test_crafting_usability` (5), ekran görüntüsü |
| Eşya/yığın/envanter | `items/*.py` | çalışıyor | Kalite bandı yığınlama, düşük kaliteden harcama, ağırlık cezası | Silah şarjörü eşyanın içinde (`loaded`) | test | `test_lowest_quality_is_consumed_first` |
| Eşya kullanma | `items/usage.py` | çalışıyor | Etkisi yoksa harcanmaz + neden; bilinmeyen anahtar raporlanır | Tıp becerisi iyileştirmeyi büyütür | kod | elle: I → Kullan |
| Fırlatılabilirler | `gear.json` (molotof, boru bombası, ses tuzağı, fişek) | **yalnızca hedef**: hiçbir sistem kullanmıyor | Eşya istatistikleri (`effects`) | T fırlatır, Y seçer. Molotof: alan yangını + yanma, **blok kırmaz**. Boru bombası: düşen hasar + yakın bloklara malzeme çarpanlı hasar (bir silahtır, kazma değildir). Ses tuzağı hordeyi çeker, fişek uzun ışık | test (molotof, boru bombası) + kod (ses tuzağı, fişek) | `test_gear_throwables_and_schematics` |
| Zırh/sırt çantası kuşanma | `gear.json` `armor`, `capacity` | **yalnızca hedef**: yalnızca açıklama metni | Veri | Envanterde Kuşan/Çıkar; zırh kaliteyle ölçeklenir ve düz hasar azaltır; çanta taşıma kapasitesini artırır; kayıtta korunur | test | `test_gear_throwables_and_schematics` |
| Loot tabloları | `items/loot.py` | çalışıyor | Ağırlıklı çekiliş, kalite doğuşta, şans | aynı | test | `test_loot_table_rolls_real_items` |
| Bina araması → **mobilya başına loot** | `systems/search.py`, `building_state.py` | çalışıyor | Süreli, gürültülü, yerinde dur, hasarda kesilir, 6 günlük yenilenme | **Cephe/ayak izi araması ve kalıntı noktası kaldırıldı.** Binalar girilebilir (`InteriorPlanner`: odalar, kapılar, merdiven, 9 yerleşim, 68 mobilya türü); her mobilya ayrı container (`<bina>:f<kat>:s<yuva>`), içerik ilk açılışta bir kez zarla, kalıcı. Tema = işlev + oda + mobilya türü. Kesinti: ilerleme saklanır, eşya verilmez (eski %50 yarım ödül bilerek taşınmadı). Loot paneli: tek/yığın/hepsi, sığmayan içeride kalır. Bina başına yenilenme bütçesi. Tahripte bir kez enkaz | test + görsel | `test_interiors` (5), `test_containers` (9), ekran: market/eczane/daire içi, loot paneli |
| Kapılar | — (yeni) | — | — | Gizli katı kapı hücreleri: aç/kapa aynı anda çarpışma, mermi, görüş, zombi rotası; gövde varken kapanmaz; silahla kırılır (kalıcı) | test | `test_interiors:test_door_state_is_consistent` |
| Bina sınıfları | `building_classes.json` | çalışıyor | OSM etiketi → sınıf → loot | Dükkân **noktaları** (node) içindeki binaya atanıyor (Kadıköy: 110 atama) | test + görsel | `test_city` |
| Silahlar | `combat/weapons.py`, `systems/weapons.py` | **kısmen**: 1–4 tuşu tüm silah tanımlarından birini seçiyordu, her birine şarjörün 6 katı bedava yedek mermi veriliyordu; envanterle bağ yoktu | Hasar, atış hızı, saçma, dağılım, geri tepme, bloom, doldurma, gürültü, delme, yakın dövüş konisi | Silah gerçek envanter eşyası; yedek cephane çantadan harcanır; modlar çarpan; kalite etkisi; dayanıklılık aşınması | test + görsel | `test_combat` (7 test) |
| Dayanıklılık | `ItemStack.durability` | **yalnızca hedef**: alan vardı, hiç azalmıyordu | — | Her atışta azalır, Tamir becerisi yavaşlatır, bozuk silah ateşlemez. Envanterden onarım: 1 metal + 2 bağlantı parçası, dayanıklılığın %40'ı (zanaat kalitesi becerisiyle ölçeklenir) | kod | elle: I → Onar |
| İsabet | `ProjectileSystem` (ışın izli mermi) | çalışıyor (2D) | Delme, en yakın hedef sırası | Hitscan; voxel+aktör tek sıralı liste; kamera ışını + namlu ışını; delme gücü malzeme direnciyle azalır; cam kırılınca mermi devam eder | test | `test_combat` |
| Blok malzemesi ve yıkım | — (yeni) | — | — | 50 malzeme (köprü çeliği, şerit çizgili asfalt, iç sıva/parke/fayans/basamak ve mesh'e girmeyen gizli katı mobilya/kapı dahil), hücre başı HP, silah çarpanı ayrı, 4 kademe çatlak, yalnızca hasarlıların HP'si saklanır | test + görsel | `test_material_hit_counts_differ` (tahta 3 atış) |
| Zombi AI | `ai/brain.py`, `systems/ai.py` | çalışıyor | FSM (boşta/dolaş/araştır/kovala/saldır/sersemle), görüş konisi, arkası kör, ses=min(yarıçap, kulak), 5 adımda bir görüş, saldırı hazırlığı ve kaçılabilirlik, bağıran tip, ısırık durumu | Voxel gövde, zıplama, kalabalık ayrışması, barikata saldırı (yalnız oyuncu bloğu) | test + görsel | `test_ai`, ekran görüntüsü |
| Yol bulma | `engine/pathfinding.py` | çalışıyor | Akış alanı, barikat = maliyet (duvar değil) | 2.5B sütun analizi voxel'den; blok değişince sütun geçersizlenir; 1 m delikten geçmez; kova kuyruklu Dijkstra kareye yayılır | test | `test_ai` (6 test) |
| Zombi yöneticisi | `world/director.py` | çalışıyor | Isı, gece ×2, özel tip oranı, görüş dışı doğum, ilk nüfus | Görüş dışı = göz ışını + bakış konisi; bina ayak izinde doğmaz (kapalı odada zombi belirmez, dışarıdan açık kapı/delikten gelir) | kod + görsel | — |
| Gün/gece | `world/daynight.py` | çalışıyor | 16 dk gün, görüş/horde/hız çarpanları, fener = risk | Güneş/ay/gökyüzü | kod | — |
| Takvimli dalga | `world/siege.py` | çalışıyor | 7 günde bir, önceden duyuru, dalga üsse yürür | Atlanan dalga gecesi (ölüm zamanı) tanımlı kuralla, bir kez çözülür | kod | — |
| Üs/yerleşim | `base/settlement.py`, `systems/settlements.py` | çalışıyor | Üs = kapatılmış sokak; sızıntı raporu; yarıçap/alan sınırı; delinince silinmez; bina rolü = kapasite; revir, susuzlukta iyileşme yok | Voxel binalar doğal duvar; oyuncu blokları kapatır; sızıntılar dünyada kırmızı sütun | kod + görsel (ekran) | elle: barikat → L → Burada üs kur |
| İnşa | `base/placeable.py`, `systems/base_building.py` | çalışıyor (2D yerleştirme) | Barikat yönlendirir, tuzak/taret/istasyon, kalite istatistiği ölçekler | Voxel blok duvarlar (katalog), önizleme+geçerlilik rengi, döndürme, destek kuralı (havada/suda yok, köprü onarılır), atomik ödeme, onarım, sökme aynı kalitede iade | test | `test_build` (8 test) |
| Koloni | `base/colony.py` | çalışıyor | İhtiyaç, iş, moral tavanı, ilişkiler, ayrılma+erzak götürme, tarım+tohum dönüşü, sefer (soyut, okunur rapor), günlük tek işlem | Aynı kayıt hem uzak (soyut) hem yakın (görünen) NPC'yi sürer: çift üretim yok | test | `test_colony` (7 test) |
| İş emirleri | `base/workorder.py` | çalışıyor | Sıralı, rezerve yok, günde 1, bilinmeyen tarif sessizce düşer | aynı | test | `test_work_order_uses_stockpile_and_recipe` |
| Nöbetçi | `colonists.py`, `colony.json` `guard_*` | kısmen (2D) | Menzil, hasar, aralık, gürültü | Her atış deponun **gerçek** fişeğini harcar; bitince uyarır | kod | — |
| NPC kurtarma / telsiz | — | **yalnızca hedef**: sakinler listeden seçiliyordu | Profil verisi | Şehirde bekleyen kişi → [E] ikna → izler → yatağı olan kapalı üste katılır; El Telsizi (yeni eşya+tarif) yön/uzaklık gösterir | kod | — |
| Beceriler/ilerleme | `progression/*.py` | çalışıyor | Toplamalı değiştirici, karesel seviye, puan, rütbe ≤5; XP: öldürme/arama/üretim | aynı | kod | elle: K |
| Yetenekler | `powers/*.py` | çalışıyor (2D) | Enerji, bekleme, rütbe ölçekleri | Yuvarlanma → ekranı döndürmeyen kaçınma atılması; itekleme yalnız düşmana; ilk yardım kanal (hasarda kesilir); dikkat dağıtma bakılan noktaya ses | kod | — |
| Ölüm | `gameplay._check_death` | çalışıyor | Üste uyan (%35 can), çanta düştüğün yerde, 48 oyun saati; üs yoksa oyun biter | Atlanan günlerde koloni/kaynak tek sefer işler | kod | — |
| Kayıt | `save/*.py` | çalışıyor | Atomik yazma, .bak yedek, bozuksa yedeğe düş | ZSTD JSON; harita+üretici sürümü; uyumsuzsa açılmaz, korunur; yükleme hatasında otomatik kayıt yazmaz; yalnızca farklar. **Kayıt v2** (container durumu, kırık kapılar) + tanımlı **v1 → v2 göçü**: arama hakları container'lara, ikinci kez ödül yok, dünya farkları korunur, oyuncu duvardaysa boş yere | test | `test_zz_integration` (5; gerçek v1 kaydıyla göç) |
| Eski 2D kayıtlar | `%APPDATA%\IstanbulZ\saves` | — | Dosyalar korunur | Okunur, listelenir, **aktarılmaz** (harita ve 3D uyumsuz) | kod | ana menü uyarısı |
| Harita | `tools/osm_import.py`, `city_format.py` | çalışıyor (54×47 km 2D) | Gerçek OSM, kıyı dolgusu, sınıf eşleme | **Varsayılan: Maltepe–Beşiktaş koridoru** (8×10 km kutu, omurga boyunca 1,1 km genişlik, 27 181 bina, ölçek 0.65). Biçim v2: kara maskesi 2 m satır RLE, arazi 4 m ızgara (çift doğrusal), bina tabanı önceden hesaplı. Kara/deniz kıyı kuralı tohumlarının oylamasıyla bulunur ve 6 bilinen noktayla doğrulanır. Koridor dışı görünür ama girilemez (VoxelWorld sınır maskesi). Sütun önbelleği iki nesilli (bellek sınırlı). Küçük Kadıköy (v1) test şehri olarak kalır | test + görsel | `test_corridor` (8 test), `test_city` |
| Harita ekranı | `ui/screens/citymap.py` | çalışıyor | Zoom/pan, üsler | Hedef işareti + HUD yön, katmanlar, oyuncuya dön. Koridorda harita görüntüsü araç tarafından hazır çizilir (4 m/piksel PNG); köprü adı katmanı | görsel | ekran görüntüsü |
| Ayarlar/tuşlar | `core/input.py`, `config.py` | çalışıyor | — | Tüm tuşlar değiştirilebilir (takaslı), hassasiyet x/y, FOV, baş sallanması, sarsıntı, görüş, gölge, ses | kod | — |
| Araçlar | `world/travel.py`, `travel.json` | **kısmen**: hızlı seyahat ve araç verisi | Araç tanımları (hız, ivme, kapasite, dayanıklılık) | Binilip sürülür (E), kolay sürüş; **blok kırmaz**, çarpınca hasar alır; güvenli iniş noktası; yakıt gerçek eşyadan; bagaj; onarım; kayıt. Park etmiş araçlar doğuş çevresinde kümelenir, köprüde terk edilmiş sıra. Egimli zeminde gömülü doğmaz (ayak izi en yüksek yüzeyi), şerit ortasına park eder. **Sürücü görüşü:** açık kabuk + kabin, model başına `driver_eye`, kabin FOV'u, şeffaf cam, serbest fare bakışı (±110°, H ortala), kollar gizli, alt orta gösterge. **Fizik:** kademeli gaz/fren, açık geri vites, hıza bağlı direksiyon, gerçek boy/en yönlendirilmiş çarpışma, 0,55 m basamak (bordur evet, 1 m duvar hayır), ≤ 0,25 m alt adım, yüklenmemiş chunk'ta hasarsız duruş, hızlıyken inilmez | test + görsel | `test_vehicles` (12), `test_corridor:test_parked_cars_can_drive`, ekran: sedan/van/minibüs sürücü görüşü |
| Köprü / Maltepe–Beşiktaş | — | — | — | 15 Temmuz Şehitler Köprüsü: iki yön yolunun orta hattı, 1007 m, ana açıklık 669 m. Voxel tabliye 30 m'de (rampa, dolgu, ayak, refüj, şerit, 2 m korkuluk), çelik kuleler; halat/askı ve uzak siluet voxel dışı dekor (görüş yarıçapı ötesinde sissiz). Deniz ulaşımı yok; yakalar arası tek kara yolu | test + görsel | `test_bridge_structure`, `test_bridge_ramp_is_walkable_and_repairable`, `test_bridge_decor_builds_near_and_far` |
| Başarımlar / Steam | `platform_services/*` | kısmen | — | — | taşınmadı (kapsam dışı bırakıldı) | — |
