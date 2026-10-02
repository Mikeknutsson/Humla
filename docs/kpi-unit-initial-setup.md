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

Den ursprungliga migreringen öppnade elva nya, obekräftade ekipage. På användarens
uttryckliga begäran återöppnades 2026-10-02 alla 13 manuella enheters grundkopplingar.
Tio låsta enheter återöppnades med audit av tidigare låsning och perioder; en var
redan öppen. Två äldre enheter saknade statusrad och fick en öppen status med
audit av oförändrade perioder. Inga projekt, grupper, startdatum eller belopp
tilldelades automatiskt.

En rättning av grundkopplingen ersätter endast första perioden. Senare perioder
bevaras. Grundkopplingens start och slut får inte överlappa nästa period.
Dashboardens grundkopplingsläge laddar första periodens innehåll, medan Ny ändring
laddar senaste innehållet. Klienten kan fortfarande inte återöppna en låst koppling.

## Verifiering 2026-10-02

- Produktionsbuild och ESLint godkända.
- SQL-test med ROLLBACK: MNJ31B kunde få historisk grundkoppling från 2025-09-01.
- DFC86A:s första period kunde rättas; senare period var identisk före och efter.
- Verklig NEXT-kostnadsrad kunde matchas till registrerat projekt, med oförändrat belopp.
- Okänt projekt nekades. Inga testregler eller ändrade perioder lämnades kvar.
- Januaris 2 280 ekonomiska fakta var identiska före och efter migreringen.

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
