# Månadsrapport Transport

Ny flik `view=monthly` i Dashboarden. En vald kalendermånad och verksamhetsårets Sep–vald månad YTD levereras som PDF eller Excel. Export sker i Dashboarden; ekonomi beräknas i Hub RPC `hub_kpi_monthly_transport_report_v1`. Ingen bokföring, importstatus eller synkmotor ändras.

Mike godkände 2026-10-06 att alla registrerade intäkter räknas som fakturerade. Detta är en explicit rapportregel, inte en ändring av Workifys originalstatus. Omsättningen följer artikeldatum och befintliga Hub-fördelningar. Kostnadsställe, verksamhetsgrupp, enhet, fordon och projekt kombineras. YTD innefattar samtliga månader från september genom rapportmånaden.

Resultatet använder NEXT-kostnader och TransPA-personalschablon och märks preliminärt. Intäkt per lastbil använder aktiva egna intäktsbärande fordonsenheter och märks uppskattning; inhyrdas samlingsenhet är ingen enskild lastbil. Verifierat fullständigt lastbilsbestånd saknas. Debiterbar tid för fordon/chaufförer saknas som verifierat mått och rapporteras därför inte som noll eller ersätts med TransPA-tid. Dieselandel visas endast när samtliga bränslerader uttryckligen avser diesel. Bränsle totalt och rapporterad TransPA-beläggning visas som separata indikatorer. Månadstäckning är radförekomst och garanterar inte ett fullständigt bokslut.

Rapporten läser samma dagligt förberedda generation som KPI. Servercache isoleras per användare, tenant, generation och urval, med ny behörighetskontroll före cacheträff. Browsercache gäller flikens livstid och töms vid Hämta underlag igen. Urvalsbyte laddar bara rapporten, inte hela sidan. RPC är avsiktligt authenticated-only SECURITY DEFINER för tillgång till privata prepared-tabeller; explicit kpi.read och tenant-kontroll görs före dataåtkomst, anonymous/PUBLIC execute är spärrat.

Verifiering: `npm run build`, riktad ESLint, `node scripts/test-kpi-monthly-report.mjs` samt samma exporttest med verklig Hub-rapport. SQL-assertioner för september 2026, januari verksamhetsår 2025/2026, YTD-summa, gemensamt KST 20+30, saknade värden och nekad anonymous/annan tenant. September KST30: omsättning 6 762 040,64 kr; preliminärt resultat 1 818 774,55 kr.
