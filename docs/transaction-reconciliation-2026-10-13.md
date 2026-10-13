# Produktionskontroll 2026-10-13

Bas: produktionscommit `99fe66630167be9c79e07ae89daf90f971b0352e`.
Arbetsgren: `feature/transaction-reconciliation-20261013`.

## Levererat

- Kostnadskontroll över hela tenantens importhistorik med 100 rader per sida och fullständiga serverberäknade totalsummor.
- Originalrad, fil, import, valideringsfel och möjlig motsvarande rad kan granskas utan att ändra data.
- Explicit inloggning, entydig aktiv tenant och `kpi.read` på sidor och RPC. Anonym och annan tenants åtkomst nekas.
- Verifikation utan unikt källrad-ID klassas som möjlig dubblett. Konflikter under samma källdokument/rad klassas som granskning för samtliga berörda rader.
- TransPA-översikt använder daterade tidrapporter och verifierade kanoniska Hub-identiteter. Saknade identiteter och flera fordon samma dag hålls för granskning. Ingen extrapolering mellan dagar.
- Tidigare applicerade Workify-migrationer finns nu i källkontrollen med databasens faktiska versionsnummer. De sparar statusobservationer separat och bevarar originalrader. Historisk korrigering har inte körts beständigt.

## Avstämningens begränsningar

Produktionsmängder och ekonomiska belopp redovisas i den behörighetskontrollerade kontrollvyn och i överlämningen till beställaren. De ska inte publiceras i detta publika repository.

Källfiler utan dokumentrad-ID kan bara ge dubblettkandidater. En verifierad nolla i kontrollen betyder att identiteten ännu inte är styrkt, inte att giltiga transaktioner saknas. Importens is_valid innehåller även fördelningskontroller och får inte jämställas med ekonomisk ogiltighet.

Workifys READ ONLY-kontroll använder innehåll och förekomst per import samt separata statusobservationer. Den omfattar giltiga, icke-nollställda intäktsrader med ordernummer. Källpartitionens matematiska avstämning är inte i sig en godkänd avstämning mot KPI. Beloppen är före KPI-omräkning, intern eliminering och fördelning.

TransPA-tidrapporterna kopplas per datum genom kanoniska identiteter. Saknade identiteter och flera fordon samma dag hindrar automatisk fördelning. Avsaknad av tidrapporter för en period bevisar inte att ingen verksamhet förekom.

Inga fördelningsregler har aktiverats av denna ändring.

## Databas och verifiering

Migration `hub_readonly_transaction_review` lägger till två privata läsfunktioner och två behörighetskontrollerade offentliga läs-RPC:er. Den ändrar inte importer, regeltabeller eller KPI-generationer. Ekonomisk fördelningsdifferens är ännu **inte fastställd**.

Verifierat isolerat i PGlite: anonym/annan tenant nekas, sidindelning utan förlust, totalsummor över alla rader, krediter, osäkra dubbletter, oförändrade original, daterade identiteter och ofullständiga fordonsreferenser. Workify-tester täcker statusbyten, gammal återimport, identiska verkliga rader, inkrementella förekomster, ändrat belopp/fordon/artikel, kredit, nollrad och historisk idempotens. TypeScript, Next-produktionsbygge och riktad ESLint godkända.

## Kvar före full ekonomisk aktivering

1. Verifiera NEXT-rader mot källsystemets dokumentrad-ID eller godkänd originalavstämning. Verifikationsnummer ensamt räcker inte. Hämta källunderlag eller bekräfta källans garanti för radmultiplicitet.
2. Granska Workifys historiska dubblettkandidater och statusändringar mot original. Den föreslagna statusavgränsningen ligger i `supabase/tests/workify_pending_status_scope.sql`, utanför automatiska migrationer; den är **inte aktiverad i KPI**.
3. Avstäm alla konsumenter och beredda KPI-fakta före eventuell historisk korrigering. Rapportgenerationer har inte byggts om.
4. Verifiera tidsbegränsade manuella matchningar, fordonsfördelning, släp/ekipage, gemensamma kostnader och verklig ekonomisk före/efter-effekt.
5. Godkänn avstämningen och aktivera först därefter berörda regler. Kontrollsidorna i sig är ingen ekonomisk aktivering.
