# Grundkoppling och verksamhetsgrupp för ekonomiska enheter

En grundkoppling är ett uttryckligen öppet utkast på samma permanenta enhets-ID.
Administratören kan komplettera projektnummer, regnummer, personreferenser och
verksamhetsgrupp samt ange ett historiskt startdatum. Varje rättning arkiverar
hela föregående utkast i `kpi_unit_initial_setup_events` innan det ersätts.

Markera **Lås grundkopplingen när jag sparar** när grundkopplingen är färdig.
Efter låsning får en ändring börja tidigast dagens datum i Europe/Stockholm och
måste börja efter senaste periodens start. Den skapar en ny period; tidigare
kopplingar och grupper bevaras. Låsningen kan inte återställas av klienten.
Att välja **Ny ändring** för en öppen grundkoppling låser den också.

Migreringen öppnar bara de elva nya, obekräftade ekipagen med en enda period
från screenshot-importen 2026-10-01. Enheter med befintlig historik (bland annat
RHR94A) återöppnas inte. Inget historiskt startdatum eller gruppval fylls i
automatiskt för produktionsdata.

**Verksamhetsgrupp · hela enheten** sparas i enhetens daterade periodpayload.
Hub prioriterar denna grupp framför projektgrupper för alla ekonomiska fakta
som entydigt tillhör enheten. Utan egen grupp gäller befintliga projektregler.
Motstridiga enhetsmatchningar eller gruppversioner förblir Ej klassificerat;
fakta och belopp finns kvar. Kostnadskategorier och styrning av om kostnaden
ingår i fordonsresultatet ändras inte.

Enhetsnamnet följer intäktsbärande huvudfordon. Personreferenser ska vara
verifierade anställningsnummer, utan namn efter numret. Detta innebär inte
att canonical Humla Person identity är verifierad.

## Verifiering 2026-10-01

- Lokal ESLint och produktionsbuild godkända.
- SQL-test i transaktion med ROLLBACK: DDL33B kunde grundkopplas från
  2025-09-01 på samma UUID. Föregående utkast arkiverades.
- 37 verkliga augustifakta, inklusive NEXT-projekt 9051 och 9052, fick samma
  enhetsgrupp. Ny senare gruppperiod ändrade inte augustis grupp.
- Låsning, nekad bakåtdatering efter låsning, nekad återöppning, nekad direkt
  klientupplåsning, nekad okänd grupp och revisionskontroll verifierade.
- Ny enhet kunde skapas som öppen grundkoppling eller låsas vid första sparning.
- Alla teständringar återställda. Inga verkliga grupper eller personkopplingar
  har tilldelats av testkörningen.
- Augusti: 2 323 fakta; omsättning 5 213 867,12 kr; NEXT 2 907 582,72 kr;
  TransPA-schablon 1 069 648,58 kr; total kostnad 3 977 231,30 kr. Oförändrat.
- Visuell slutkontroll är blockerad av testwebbläsarens observationsfel.
