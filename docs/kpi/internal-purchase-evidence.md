# Interna Transporter – inköpsunderlag

Inköp och materialmellanskillnad beräknas av Hub-RPC `hub_kpi_internal_transfers_with_purchase_v1`. Dashboard renderar värdena och exporterar Excel. Originalintäkter, identiteter och omföringsledger ändras inte.

- Bilagor läses en gång per URL och tenant. Källans SHA-256, avläst täkt/fraktion/datum, kvittoreferens och granskningsstatus bevaras privat i Hubben.
- OCR är preliminär. Kvittomängd räknas bara när bilagan är manuellt granskad, datum/fraktion stämmer, mängden inte överstiger orderraden och bilagan inte delas av flera rader med samma artikel.
- Delkvittots mängd och beräknade kostnad hålls isär från hela radens preliminära inköp.
- Exakt täkt matchas mot daterad nettoprislista. Björklunds särskiljs per täkt.
- Täkt från kvitto på en order ärvs av orderns övriga materialrader, även utanför aktuellt periodurval. Ett entydigt radkvitto har företräde. Flera täkter eller oläsliga kvitton utan fastställd täkt kräver granskning; inga kvittomängder sprids. Finns inga kvitton används entydiga kommentarer på samma order och därefter medelprisregeln.
- Utan fastställd täkt används Mikes uttryckliga medelprisregel: samma fraktion hos Johanssons, Schweden Splitt och Vambåsa. Tillgängliga prisers antal och källor visas. Kända täkter utan exakt pris får inte ett godtyckligt annat täktpris.
- Vambåsa/Össjö/Önnestad använder sista nettopriskolumnen; rabatt dras inte igen. Schweden saknar giltighetsdatum och markeras preliminär.
- Kylinges befintliga 2025-prisgrund behålls. Den tidigare godkända december-PDF-prislistan används endast som ett uttryckligt augusti-2026-undantag; den skrivs inte bakåt över andra månader.
- Tvetydig fraktion, specialprodukt, inköp på kundens konto och saknad mängd/inköpsgrund hålls utanför beräknad kostnad. Saknad kostnad är null, inte noll.
- Tippkostnad kräver separat pris-/fakturaunderlag. Transportartiklar får inte materialinköp.

`Exportera inköpsunderlag – alla orderrader` är en rapportexport för period/KST, även granskningsrader. Den bokför eller markerar inget som omfört. Befintlig färdigdataexport behåller sin avgränsning.

Första genomgången 2026-10-06 omfattade 4 660 interna importrader och 301 unika bilagor. Pris- och kvittoevidens är sparad i Hubben. Nyimporterade bilagor utan avläsning visas uttryckligen som `not_read`; detta arbete inför ingen ny kontinuerlig OCR-tjänst.
