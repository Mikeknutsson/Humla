# Interna Transporter – inköpsunderlag

Inköp och materialmellanskillnad beräknas av Hub-RPC `hub_kpi_internal_transfers_with_purchase_v1`. Dashboard renderar värdena och exporterar Excel. Originalintäkter, identiteter och omföringsledger ändras inte.

- Bilagor läses en gång per URL och tenant. Källans SHA-256, avläst täkt/fraktion/datum, kvittoreferens och granskningsstatus bevaras privat i Hubben.
- OCR är preliminär. Kvittomängd räknas bara när bilagan är manuellt granskad, datum/fraktion stämmer, mängden inte överstiger orderraden och bilagan inte delas av flera rader med samma artikel.
- Delkvittots mängd och beräknade kostnad hålls isär från hela radens preliminära inköp.
- Exakt täkt matchas mot daterad nettoprislista. Björklunds särskiljs per täkt.
- Täkt från kvitto på en order ärvs av orderns övriga materialrader, även utanför aktuellt periodurval. Ett entydigt radkvitto har företräde. En enda täkt bland tolkade kvitton används som en uttrycklig sannolikhetsbedömning för orderns övriga materialrader. Antagandet och antalet stödjande bilagor sparas; inga kvittomängder sprids. FilUrl och URL-bilagor i Platser ingår i orderunderlaget. Flera täkter eller oläsliga kvitton utan fastställd täkt får schablonavdrag från de tre täkternas medelpris när fraktion, mängd och tre giltiga priser finns; kvittogranskningen kvarstår. Finns inga kvitton används entydiga kommentarer på samma order och därefter medelprisregeln.
- Utan fastställd täkt används Mikes uttryckliga medelprisregel: samma fraktion hos Johanssons, Schweden Splitt och Vambåsa. Tillgängliga prisers antal och källor visas. Kända täkter utan exakt pris får inte ett godtyckligt annat täktpris.
- Vambåsa/Össjö/Önnestad använder sista nettopriskolumnen; rabatt dras inte igen. Schweden saknar giltighetsdatum och markeras preliminär.
- Kylinges befintliga 2025-prisgrund behålls. Den tidigare godkända december-PDF-prislistan används endast som ett uttryckligt augusti-2026-undantag; den skrivs inte bakåt över andra månader.
- Tvetydig fraktion, specialprodukt, inköp på kundens konto och saknad mängd/inköpsgrund hålls utanför beräknad kostnad. Saknad kostnad är null, inte noll.
- Bekräftad regel 2026-10-09: intern tippavgifts satt Workify-radbelopp används även som inköpskostnad, med bibehållet tecken för krediter/negativa priser. Mellanskillnad är noll. À-pris härleds från radbelopp/mängd; om mängd saknas kan källans Kundpris visas medan det kända radbeloppet fortfarande är kostnadsgrund. Saknat belopp blir null, aldrig gissat noll. Prisstatus `tipping_set_price` och prisunderlag beskriver den bekräftade kostnadsschablonen, inte en verifierad leverantörsfaktura. Kvittomatchad kostnad/mängd och täktprissampling används inte för tippavgiften. Transportartiklar får inte materialinköp. Ingen extra KPI-kostnad, omföring eller ledgerändring skapas; regeln gäller det separata interna inköpsunderlaget och dess Excel-export.

`Exportera inköpsunderlag – alla orderrader` är en rapportexport för period/KST, även granskningsrader. Den bokför eller markerar inget som omfört. Befintlig färdigdataexport behåller sin avgränsning.

Första genomgången 2026-10-06 omfattade 4 660 interna importrader och 301 unika bilagor. Pris- och kvittoevidens är sparad i Hubben. Nyimporterade bilagor utan avläsning visas uttryckligen som `not_read`; detta arbete inför ingen ny kontinuerlig OCR-tjänst.
