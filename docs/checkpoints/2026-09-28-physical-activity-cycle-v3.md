# Checkpoint – Physical Activity / Cycle Reconstruction
Datum: 2026-09-28

## Status
Humla Hub har nu en Activity Profile-baserad grund för tolkning av fysisk aktivitet. Fordonstyp styr hur GPS-stopp och andra signaler ska tolkas. LMT31J är kopplad till profilen `haulage_truck`.

## LMT31J testdag
Test: 2026-09-17.
- GPS/XML: 1 109 observationer.
- 229 observationer har nu onboard-vikt backfillad från originalfilen.
- Högsta registrerade bruttovikt: 69 800 kg.
- Verifierade våghändelser: 6.
- Order 44523: 4 vågningar, totalt 170,49 ton.
- Order 44544: 2 vågningar, totalt 60,73 ton.

## Cycle Reconstruction v3
Funktion: `hub_reconstruct_transport_cycles_gps_v3(uuid)`.
Metod: `profile_weight_gps_v3`.
Den använder Activity Profile + GPS + viktförändring + verifierade våghändelser.
Testkörning LMT31J gav 8 fysiska delsegment. Confidence är högre när vågdata/viktförändring stöder segmentet.

## Weighing → cycle
Funktion: `hub_bind_weighings_to_cycles_v2(uuid)`.
Alla 6 våghändelser kan förankras, men nuvarande cykelgränser gör att:
- 44544: korrekt 2 separata cykler / 60,73 ton.
- 44523: bara 3 separata cykler / 127,88 ton.
Det betyder att två verifierade våghändelser fortfarande kan hamna på samma fysiska cykel.

## Nästa steg – viktigt
Bygg generell split-logik:
1. En verifierad våghändelse ska kunna kräva en egen lastcykel.
2. Om två verifierade våghändelser hamnar i samma rekonstruerade cykel ska cykeln delas vid bästa fysiska brytpunkt mellan dem.
3. Brytpunkt väljs med viktfall/viktökning, stopp, GPS/rörelse och Activity Profile.
4. Därefter 1:1-koppling WeighingEvent → lastcykel → TransportOrder.
5. Ingen specialkod för LMT31J eller order 44523/44544.
6. Om vågdata saknas fortsätter GPS + viktmönster att rekonstruera med lägre confidence.
7. Första framkörningen ska ekonomiskt allokeras till första uppdraget och sista hem/positioneringskörningen till sista uppdraget, men dessa får inte räknas som loaded km eller ton-km.

## Mål för regressionstestet
LMT31J 2026-09-17 ska efter generell split ge:
- 44523: 4 lastcykler, 170,49 ton.
- 44544: 2 lastcykler, 60,73 ton.
Detta är verifieringsfacit, inte hårdkodad logik.

## Arkitekturprincip
Physical Activity ska beskriva vad som faktiskt hände. Ordermatchning/allokering ligger ovanpå den fysiska rekonstruktionen. Activity Profile avgör hur signalerna ska värderas per fordonstyp. Saknade signaler sänker confidence men ska normalt inte stoppa flödet.
