# Humla Chaufför – utvecklingsversion

Separat mobilgränssnitt på `/forare`, personlig inloggning på `/forare/login`. Befintliga `/chauffor` med KPI-funktioner är oförändrade. Mobilgränssnittet har Humlas gula profil, mörkgrå topp, stora knappar och statusfärger. Manifest och ikon för hemskärmsgenväg. Ingen service worker eller offlinegaranti.

## Implementerat

- Endast verkliga hub_transport_orders tilldelade den inloggades kanoniska Person-ID. Testportalens order och Workify-intäktsreferenser ingår inte.
- Återanvänder private.hub_driver_account_links med giltighetsdatum, befintlig kontokoppling på `/chauffor/admin`. Ingen automatisk namn-/e-postmatchning eller administratörsimpersonering.
- Aktiv organisation och transport.assignments.read krävs; worker får den avgränsade behörigheten. Inga användarkonton, personkopplingar eller skarpa order skapade.
- Aktuella uppdrag, Att rapportera och Inskickade; orderdetaljer, planerade artiklar utan priser, instruktion, plats/kartlänk, telefonkontakt.
- Start, paus, fortsätt, spara återrapportering, bekräfta avslut. Timmar, hela lass, ton och kommentar/avvikelse.
- Servern verifierar aktuell tilldelning vid varje läsning/skrivning. Pris, inköpspris, belopp och internanteckningar lämnar inte den skyddade läsgränsen. Endast explicit valda fält returneras.
- Rapportering sparas som driverReport på samma order. Ändringshistorik får användare, serverklockslag, före/efter och version. Kommando-ID gör retries idempotenta; ändrad payload med samma nyckel avvisas. Versionskontroll skyddar samtidiga ändringar. Om tilldelningen dras tillbaka fungerar inte heller repris av tidigare kommando.
- Avslut ger Utförd (fortfarande redigerbar). Först knappen Rapporterad skickar till transportledningen och låser. Ingen automatisk Faktureringsklar-status. Rapporter ändrar inte artikelpriser, planerade mängder, intäkt eller lönerapportering. Transportledningen ska granska utfört underlag.
- Vid anslutningsfel visas fel och formulärets värden ligger kvar i den öppna sidan. Sparstatus påstås inte förrän servern bekräftat. 20 sekunders nätverkstimeout.

## Verifiering

Next/TypeScript build godkänd. SQL-rollbacktest transport_driver_app.sql godkänt för tilldelningsfilter, skyddade fält, start/paus/fortsätt/rapport/avslut, idempotens, nyckelåterbruk, versionskonflikt, oförändrade priser, historik, återkallad tilldelning, utgången personkoppling, organisationsisolering och grants. Alla testskrivningar återställda.

## Kvar innan komplett chaufförsflöde

Transportledningens gränssnitt behöver fortfarande anslutas till driftordermodellen; den nuvarande orderportalen skapar testorder. Därför är appen tom utan tilldelade driftorder och bekräftad personkoppling. Mottagna rapporter finns nu i en läsvy på `/orderportal/rapporter`; godkännande, retur för komplettering och faktureringsflöde återstår.

Bilder, vågsedlar, tillägg/ändring av artikelmängder, pushnotiser och full offlinekö är inte implementerade. Inmatning överlever inte omladdning/offline-omstart; ingen användarspecifik cache läggs på delade telefoner. Paushistorik sparas men timmar beräknas inte automatiskt. Ingen separat TransPA- eller faktureringsexport.

Ingen driftsättning till produktionsdomänen. Publiceras enbart som utvecklingsförhandsversion. Visuell kontroll på riktig mobil och installation på iPhone/Android återstår.

## Överlämning 2026-11-13

- Flöde: Planerad → Pågående → Utförd / Att rapportera → Rapporterad / Inskickad. Spara utkast lämnar ordern redigerbar. Bekräftad Rapporterad skickar aktuella formulärvärden, status och serverns inskickningsstämpel i samma transaktion som historik och idempotenspost.
- Alla chaufförskommandon blockeras efter inskickning. Repris av exakt tidigare kommando ger samma resultat utan ny ändring. Versionskontroll gäller vid nya kommandon.
- Inskickningsstämpel och chaufförens rapport bevaras vid transportledningens vanliga sparande; ett statusbyte kan inte råka låsa upp för chauffören. Återöppning är ännu inte implementerad.
- Behörighetskontrollerad, paginerad mottagningsvy för driftorder på `/orderportal/rapporter`. Kräver transport.orders.manage både i sidan och via befintlig RLS. Ingen separat orderkopia eller intäkt skapas.
- Demo `/forare/demo` simulerar samma flöde lokalt och skickar inget till mottagningsvyn eller databasen.
- SQL-test verifierar komplettering efter Utförd, inskickning, samtliga sex blockerade chaufförskommandon efter inskickning, idempotens, historik och bevarad låsning efter ledningens statusbyte. Rollback efter test.
- Säkerhetsrådgivaren kontrollerad: privata kommandotabellens avsiktliga default-deny RLS utan policy är oförändrad. Ingen ny publik definer-funktion eller tabellåtkomst. Mobil webbläsarkontroll återstår.
