# Månadsrapport Transport

Ny flik `view=monthly` i Dashboarden. En vald kalendermånad och verksamhetsårets Sep–vald månad YTD levereras som PDF eller Excel. Export sker i Dashboarden; ekonomi beräknas i Hub RPC `hub_kpi_monthly_transport_report_v1`. Ingen bokföring, importstatus eller synkmotor ändras.

Mike godkände 2026-10-06 att alla registrerade intäkter räknas som fakturerade. Detta är en explicit rapportregel, inte en ändring av Workifys originalstatus. Omsättningen följer artikeldatum och befintliga Hub-fördelningar. Kostnadsställe, verksamhetsgrupp, enhet, fordon och projekt kombineras. YTD innefattar samtliga månader från september genom rapportmånaden.

Resultatet använder NEXT-kostnader och TransPA-personalschablon och märks preliminärt. Intäkt per lastbil använder aktiva egna intäktsbärande fordon, räknade en gång även om enhetskopplade och fallbackrader finns parallellt och märks uppskattning; inhyrdas samlingsenhet är ingen enskild lastbil. Verifierat fullständigt lastbilsbestånd saknas. Debiterbar tid för fordon/chaufförer saknas som verifierat mått och rapporteras därför inte som noll eller ersätts med TransPA-tid. Dieselandel visas endast när samtliga bränslerader uttryckligen avser diesel. Bränsle totalt och rapporterad TransPA-beläggning visas som separata indikatorer. Månadstäckning är radförekomst och garanterar inte ett fullständigt bokslut.

Rapporten läser samma dagligt förberedda generation som KPI. Servercache isoleras per användare, tenant, generation och urval, med ny behörighetskontroll före cacheträff. Browsercache gäller flikens livstid och töms vid Hämta underlag igen. Urvalsbyte laddar bara rapporten, inte hela sidan. RPC är avsiktligt authenticated-only SECURITY DEFINER för tillgång till privata prepared-tabeller; explicit kpi.read och tenant-kontroll görs före dataåtkomst, anonymous/PUBLIC execute är spärrat.

Verifiering: `npm run build`, riktad ESLint, `node scripts/test-kpi-monthly-report.mjs` samt samma exporttest med verklig Hub-rapport. SQL-assertioner för september 2026, januari verksamhetsår 2025/2026, YTD-summa, gemensamt KST 20+30, saknade värden och nekad anonymous/annan tenant. September KST30: omsättning 6 762 040,64 kr; preliminärt resultat 1 818 774,55 kr.


## Piusi/NEXT och TransPA, 2026-10-06

Rapportens bränslemodell är Piusi-tankningskostnad plus övrigt NEXT-bränsle. Konto 5360 (inköp till egen tank) tas bort från bränslet under månader med Piusi-underlag och visas som avstämning. Piusi-priser är preliminära om inte manuellt godkända; extrema, avvisade eller okopplade rader ingår inte. Rapportens resultat ersätter sin ursprungliga NEXT-bränsledel med denna förbrukningsmodell och kan därför skilja sig från KPI:s inköpsbaserade resultat. API/prisstatus, senaste synkning och granskningsantal framgår i vyn/exporten.

Piusi FuelTransaction och prisgranskningar kopieras till samma prepared generation av den befintliga rapportarbetaren. Schema/tider för integrationerna ändras inte. Synkfel i Piusi rättas inte av rapportfunktionen. Backfill av aktiv generation fångades separat 2026-10-06 och visas i source_state.captured_at. Bränslefiltrering använder canonical vehicle_id och befintliga daterade registreringskopplingar/enhetsperioder. Enhetslistan hämtas från exakt samma Hub economic_units som KPI; inga parallella enhetsregister skapas. Namn/kopplingar uppdateras i båda vid nästa förberedda rapportsynkning.

Arbetad chaufförstid, intäktskopplad tid, fordonstid och kapacitet kommer från Hub:ens TransPA-underlag för månad och YTD. Beläggning samt chaufförernas intäktskopplade tidsandel är tydligt märkta indikatorer, inte verifierad debiterbar tid. Användaren återtog förslaget att ersätta debiterbar tid med fakturerbar summa: detta är inte infört.

Verifierat september KST30: Piusi 503 638,03 kr; NEXT exklusive egen tank 335 432,75 kr; bränsle 839 070,78 kr; undantaget konto 5360 68 227,99 kr. Rapporterad fordonstid 4 323,57 h; arbetad chaufförstid 4 448,08 h. 44 kostnadsenheters ID:n matchar KPI-snapshoten. Excel innehåller 11 blad inklusive bränsle- och TransPA-underlag samt samma kostnadsenheter för månad och YTD.
