# Arbetsledarnas personliga styrkort (transport)

## Grundregel
Användarens Supabase Auth-ID avgör vilken ekonomisk enhet som tillhör vyn. Ingen klientparameter får utöka en arbetsledares åtkomst. Avdelningschef/owner får vid behov välja annan arbetsledare, men inget standardbehörighetslyft ges till vanliga transportledare.

## Implementation i denna etapp
- `hub_transport_leader_units`: explicit och tidsavgränsat ansvar per **befintlig** `kpi_units` (enhet), per organisation och inloggad användare.
- Fail closed: inga tilldelningar innebär **inga enheter**, aldrig automatiskt alla.
- `hub_transport_leader_units_for_user` verifierar session, organisation och eventuell owner-behörighet på serversidan.
- Startsidan `/transport-styrning` visar individuellt tilldelade enheter. Nya användare/ansvar måste först registreras och få godkända tilldelningar.
- KPI-värden ska hämtas via nya **server-side scope-aware aggregeringsfunktioner i Hub**, inte via filtrering av totalsummor från KPI-vyn. Fram till dess visas inga missvisande ekonomiska tal.

## Styrtal att ansluta (definitioner behöver beslutas)
Dagligen: morgondagens kapacitet/beläggning, ej planerade enheter, avslutade ej faktureringsklara order.
Veckovis: fakturerad extern intäkt per aktiv fordonsdag, debiteringsgrad (endast faktisk debiterbar tid), rapporterade chaufförstimmar, övertid och inhyrning.
Månadsvis: påverkbart täckningsbidrag, drivmedel i kr/mil och andel av externa intäkter, fullständig kostnad och riskposter separat.
Visa alltid nämnare, källa, period, historiska förflyttningar och undantag såsom fordonsbyte MNJ31B → NDF59M.

## Återstående
Admin-gränssnitt för tilldelning av arbetsledare/enheter, gruppbaserade mass-tilldelningar med tillämpning vid framtida nya enheter, scope-aware KPI-RPC och tester för tenant-isolering. Denna migration är förberedd på gren, inte installerad i produktion.
