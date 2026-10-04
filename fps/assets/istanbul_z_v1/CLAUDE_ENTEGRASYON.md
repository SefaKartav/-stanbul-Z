# Claude Code — Istanbul-Z 300 model entegrasyon notu

Bu bir asset teslimidir. Önce projedeki AGENTS/talimatlar ve gerçek asset yükleyicisini incele. 300 GLB'nin dosyada bulunması 300 assetin oyuna bağlandığı anlamına gelmez.

## Manifest

`manifest.json` eski 94 kaydı aynen tutar. `manifest_additions.json` 206 yeni kayıt taşır. `manifest_combined_300.json` yardımcı birleşik listedir. Kimlik çakışması kontrolü yaparak gerçek projeye ekle. Eski kimlikleri değiştirme; `storage_crate` ve `loot_chest_wood` farklı modellerdir. Tabela/ikon/preview dosyaları GLB sayısına dahil değildir.

## Girilebilir iç mekân

Yeni brief bina içine girmeyi ister; önceki README'deki bina içine girmeme maddesi bu paket için geçersizdir. Voxel bina kabuğu, kapı boşluğu, odalar, merdiven ve yıkım oyun tarafından üretilir. Asset olarak mobilya, açıklığı olan kapı ve ekipman verilir.

Package A'daki 15 zorunlu kimlik manifestte vardır. Öncelikle `loot_chest_wood`, `wardrobe_apartment`, `dresser_apartment`, `fridge_apartment`, `pharmacy_shelf`, `market_shelf` ile bir oda/market denemesi kur. Aranabilir mobilyaya tek envanter bağla. İçerideki ganimet ayrı eşya instance'ı olsun; sabit mobilya geometrisinden loot üretme.

GLB node adları korunmalı. `open` ve `close` klipleri loop yapmaz. Collider önerileri hareketli node'lara göre yereldir. Kapı/çekmece açılırken node ve collider birlikte hareket etmeli. Animasyonun sonunda durumu kaydet. Oyun verisiyle bağlanmadığı sürece boş model kendiliğinden ganimet üretmez.

Duvar dolapları için metadata montaj yüksekliğini; ahşap/metal/mağaza kapılarında yaklaşık 1.0 × 2.1 m net açıklığı kontrol et. Gerçek karakter kapsülüyle geçiş testini uygula. Modelin dış bounds'undan tek büyük collider üretme.

## Sürüş

`vehicle_compatibility.json` tablosunu kullan. Eski dolu model yeni kabin ile aynı anda görünmemeli. Her araç için `*_shell_open` ve `*_cabin` kökleri aynı transformdadır. Taksi/polis/ambulans ayrı boyutları için ayrı kabin taşır. Koddan göz kararı scale yapma.

`driver_eye` kameranın yerel konumu, bakış −Z, yatay FOV 82° örneğiyle hazırlanmıştır. Motorunuz dikey FOV kullanıyorsa 16:9 için yaklaşık 52.1° dikey FOV'a karşılık gelir; en-boy oranı değişince dönüştür. `driver_seat` oturma önerisi, `exit_left/right` yalnız çıkış adaylarıdır: duvar/su/engel kontrolü yapmadan teleport etme. Empty node'ları gerekirse Marker3D'ye dönüştür.

`steering_wheel` ve ibreler yerel Z çevresinde, araç tekerlekleri yerel X çevresinde döndürülebilir. Ayrı tekerlek pivotlarını koru. `gear_lever` taban pivotu taşır. Araç parçalarının fizik/hasar ilişkisi bu paketin içinde yoktur.

Yeni cam ayrı mesh ve saydam materyaldir. `glass_` node'larını kapatınca görüş hattı açık kalmalı. Opak eski camı yeni camın altında bırakma. Saydam materyalin motor içi draw order/depth ve gölge davranışını doğrula.

## Kabul kontrolü

- Bir modelden her kategori için import, vertex color, ölçek ve sert normal kontrolü.
- Kapı açıkken gerçek net açıklıktan karakter geçişi; dolap içinin boş görünmesi.
- Üç çekmecenin -Z'ye çıkması, kapakların dışarı/yukarı açılması; collider'ın doğru node'u takip etmesi.
- Sürücüye bin/iniş, altı araçta ayrı eye noktasından ileri/yan görüş; direksiyon/gösterge hareketi.
- Mobilya araması yalnız bir kez tüketim/ödül üretir; tekrar aç/kapa veya yükle ile loot çoğalmaz.
- Önce küçük sahnede test; yoğun yerleşimde mesh/collider sayısı ve bellek ölçümü.

`validation_report.json` dosya kontrolleridir; motor veya oynanış testi değildir.
