class_name Units
extends RefCounted
## Eski 2D veri birimlerini FPS metrelerine ceviren TEK yer.
##
## Eski oyun "dunya pikseli" kullaniyordu: 32 px'lik karo = 2 m, yani
## 16 px = 1 m (constants.METERS_PER_TILE). JSON dosyalari bu birimle
## yazilmis ve dengelenmistir; onlari elle metreye cevirmek yuzlerce sayiyi
## yeniden dengelemek demekti. Bunun yerine cevrim burada yapilir ve UC
## ayri olcek kullanilir:
##
##   * MOVE -- hiz, ivme, saldiri menzili: birebir 1/16. Zombinin sana
##     yetisme suresi ve vurus mesafesi eski oyundakiyle ayni kalir.
##   * PERCEPTION -- gorus, duyma ve gurultu yaricaplari: 1/16 x 2. Ustten
##     bakista ekran ~60 m genisligindeydi; FPS'te sokak boyunca 150 m
##     gorulur. Olcek UCUNE BIRDEN ayni uygulandigi icin "silah sesi hangi
##     zombiye ulasir" orani degismez.
##   * WEAPON RANGE -- 1/16 x 3. 420 px'lik tabanca menzili 26 m idi; FPS'te
##     bu, sokagin karsisini vuramamak demekti. Dagilma (derece) degismedigi
##     icin isabet hala mesafeyle duser.
##
## Bu oranlar ilk dengeleme onerisidir; oynanarak ayarlanacak tek yer burasi.

const PX_PER_M := 16.0
const PERCEPTION_SCALE := 2.0
const WEAPON_RANGE_SCALE := 3.0
## Gercek olcek dengesi (25 Eylul 2026): oyuncu 4.3/6.8 m/sn yerine yuru
## 1.7 / kos 3.6 / depar 5.6 m/sn. Zombiler ayni oranda (x0.82) yavaslatilir;
## 'kosarak kacilir, yururken yetisilir' iliskisi korunur.
const ZOMBIE_MOVE_SCALE := 0.82


static func move_m(px: float) -> float:
	return px / PX_PER_M


static func zombie_move_m(px: float) -> float:
	return px / PX_PER_M * ZOMBIE_MOVE_SCALE


static func perception_m(px: float) -> float:
	return px / PX_PER_M * PERCEPTION_SCALE


static func weapon_range_m(px: float) -> float:
	return px / PX_PER_M * WEAPON_RANGE_SCALE
