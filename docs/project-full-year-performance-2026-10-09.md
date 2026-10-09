# Projektuppföljning: långsam helårsladdning

Helår 2025/2026 på alla KST tog 41,843 sekunder i EXPLAIN ANALYZE.
Databasens normala rapportgräns är 45 sekunder. Periodväljaren spärrar
knapparna under React-navigationen; användaren kunde därför uppleva vyn som låst.
Vercel visade inga registrerade runtime-fel för projektrouten vid undersökningen.

## Orsak och ändring

- En SQL-kundklassificerare bytte search_path per anrop och kunde inte inlineas.
  Den anropades per underlagsrad. Samma regel körs nu utan SET-kontextbyte.
  Alla funktioner OCH operatorer är explicit bundna till pg_catalog, funktionen
  är SECURITY INVOKER och läser inga tabeller. Behörigheter ändras inte.
- Ett filter med alla tolv månader applicerade ändå EXTRACT på varje datum.
  Planeraren uppskattade då vissa stora delmängder till cirka en sextondel av
  verklig storlek. Tolv UNIKA månader normaliseras nu internt till inget extra
  månadsfilter; datumintervallet och urvalsmetadata behålls. Delmånadsurval är
  oförändrade och avräkning mot 4600 görs fortsatt på hela valt projekturval.
- Projektvyn har nu en tidsgräns på 48 sekunder för RPC-hämtningen, före
  sidans maxDuration på 60 sekunder. Fel visar inga preliminära belopp.
- Laddningsvyn visar när hämtningen fortfarande pågår och ger en vanlig länk
  för att avbryta navigeringen och visa första månaden med samma projektfilter.
  En sådan navigation kan inte garantera att ett redan startat databasjobb
  stoppas omedelbart; databasens egen tidsgräns gäller fortfarande.

## Verifiering

- Kundregel: 1 068 namn/testfall, inga ändrade klassningar; Elleholms Stena
  fortsätter vara extern.
- Fullt autentiserat rapportanrop efter ändring: EXPLAIN ANALYZE 22,490 sekunder.
  Detta är en mätning, ingen garanterad svarstid under annan belastning.
- Före/efter samma digest på HELA JSON-rapportsvaret:
  `1c80bca4064d7bc79462d1938bc6bfae`. Belopp, projekt, månader, källor,
  internavräkning och avstämningsdiagnostik är identiska.
- Period-, interntransfer- och Workify-regressioner passerar. TypeScript och
  riktad ESLint passerar.
- Security advisor flaggar heuristiskt en rörlig search_path på den privata
  klassificeraren, eftersom den avsiktligt saknar SET för att möjliggöra
  inlining. Granskad: inga obundna funktioner/operatorer, tabelluppslag,
  SECURITY DEFINER eller behörighetsutökningar finns i den funktionen.

Historiska projekt som saknar säker registerkoppling redovisas fortsatt separat.
Denna ändring påverkar prestanda och laddningsbeteende, inte underlagets täckning.
