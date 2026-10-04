# Araç kabuk / kabin eşlemesi

Eski dış modeller korunmuştur; dolu geometri yüzünden yeni kabinlerle birlikte gösterilmemelidir.

| Eski model | Yeni dış kabuk | Yeni kabin | Hizalama |
|---|---|---|---|
| sedan | sedan_shell_open | sedan_cabin | Konum 0,0,0; dönüş yok; ölçek 1 |
| taxi | taxi_shell_open | taxi_cabin | Konum 0,0,0; dönüş yok; ölçek 1 |
| police_car | police_car_shell_open | police_car_cabin | Konum 0,0,0; dönüş yok; ölçek 1 |
| van | van_shell_open | van_cabin | Konum 0,0,0; dönüş yok; ölçek 1 |
| minibus | minibus_shell_open | minibus_cabin | Konum 0,0,0; dönüş yok; ölçek 1 |
| ambulance | ambulance_shell_open | ambulance_cabin | Konum 0,0,0; dönüş yok; ölçek 1 |

Her yeni çift aynı aracın referans uzayındadır. Kamera noktaları interaction_metadata.json ve GLB içindeki driver_eye node’undadır. Her araç için üç görüş driver_views/ klasöründedir.