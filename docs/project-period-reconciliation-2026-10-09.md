# Projektuppföljning: period och källavstämning

Kontrollerat 2026-10-09. Beräkningar, källval, canonical-ID och avräkning mot konto 4600 ägs av Hubben. Dashboarden skickar val och visar färdiga belopp. Ingen automatisk identifiering av saknade historiska projekt har införts.

## Publicerad funktion

`hub_kpi_project_report_v5` behåller v4:s ekonomiska regler, men stödjer valda månader inom datumintervallet, returnerar verksamhetsgrupper med belopp i samma anrop och redovisar källavstämning och saknade projekt. Gruppalternativen påverkas av KST, projektledare och period, inte av redan valda grupper eller ett drilldown-projekt.

Dashboarden återanvänder KPI:s verksamhetsår (september–augusti), årsväljare, flermånadsval och YTD. Detaljlänkar, sidväxling, export och interna underlag behåller månadsurvalet. Gamla länkar med egna datumintervall fortsätter fungera. Datumväljaren strömmas före rapporten; fel i Hub-anropet tar inte bort kontrollerna. Projektlänkar förhämtas inte och ett extra helårs-RPC för gruppalternativ behövs inte längre.

## Kontrollerat helår 2025-09-01–2026-08-31

| Källa | Intäkt kr | Kostnad kr |
| --- | ---: | ---: |
| NeXT, säkert registerkopplade projekt | 78 448 445,16 | 113 433 928,29 |
| Workify, externa intäkter KST 20/30 | 41 441 705,01 | 0,00 |
| TransPA, beräknad transportpersonal | 0,00 | 8 637 812,26 |
| Workify intern, intäkt respektive kostnadstillägg | 5 896 674,84 | 417 185,29 |
| Totalt i rapportens kopplade projekt | 125 786 825,01 | 122 488 925,84 |

Resultat 3 297 899,17 kr. Månadssummor, projektsummor och källsummor överensstämmer med totalsummorna på öret. NeXT-beloppen har även jämförts med en separat klassificering av samtliga råa bokföringsrader. Intern mottagarkostnad 8 581 247,35 kr, avräknad del 8 164 062,06 kr, återstående kostnadstillägg 417 185,29 kr. Avräkningen görs per projekt och vald period, inte genom summan av separata månadsavräkningar.

## Viktig begränsning: inte komplett företagsresultat

472 projekt med 8 021 NeXT-rader ligger utanför rapportens säkert kopplade register: kostnader 77 343 330,10 kr och intäkter 60 037 663,41 kr för 2025/2026. Beloppen inkluderar både projekt som saknas i registret och projekt utan säker registrering/KST. Workify/TransPA inom rapportens KST-scope har ytterligare 4 646 ej hänförbara faktarader: kostnader 1 189 734,68 kr och intäkter 16 765 806,41 kr. Dessa är diagnostik, inte summor att okritiskt lägga till resultatet. Källorna har olika intäktsregler och vissa rader kan avse samma verksamhet.

Aktuell period 2026-09-01–2026-10-09 gav före UI-publiceringen intäkter 12 846 670,82 kr och kostnader 13 492 493,46 kr. Separat rådataavstämning visar också NeXT-projekt utanför registret: kostnader 4 569 308,02 kr och intäkter 3 413 242,10 kr. Även aktuellt utfall är därför bara de kopplade projekten.

Alla 19 importbatcher granskades. Fem felaktiga/överlappande äldre batcher är återtagna med bevarade original och återställningsmetadata. 2 037 avstämda fakturor används inte som extra intäkt. Kontroll mot aktiv Hub-generation: noll fakta från återtagna batcher eller dessa avstämda fakturor; noll dubbla faktanycklar för TransPA/Workify.

21 separata fakturor saknar matchande bokförd NeXT-intäkt i exporter och ingår inte i projektvyn som bokföring. Deras netto är 1 568 564,35 kr. Möjliga identiska originalrader inom filer är fortfarande inte bevisade dubbletter: 88 möjliga extra kostnadsrader (986 185,71 kr) och 178 möjliga extra Workify-rader (80 631,12 kr, inklusive nollrader). Unika källrad-ID eller originalverifikationer krävs; inga sådana rader har godtyckligt raderats.

Kontot 4015 är klassificerat som personal i befintlig kontomappning trots beskrivningen interna transporttjänster. Detta påverkar kategori/personalsubtotal, inte total kostnad. Ingen befintlig bekräftad kontomappning har skrivits över. Kontrollpanelen äger ändring av kontoregler och projektkopplingar.

## Verifikation

- Authenticated Hub-anrop: helår, aktuell period, icke sammanhängande månader och enskilt projekt.
- September + januari innehåller bara dessa månader; KST 10 innehåller inga andra KST; källkostnad minus total = 0.
- Projekt 12716 i september: internt tillägg 0 eftersom Workify täcks av 4600. Radkostnadstillägg summerar exakt till projektsumman och alla detaljer ligger inom perioden.
- Periodtester täcker Stockholm-gränsen vid nytt verksamhetsår, godtyckliga månader, gamla länkar, ogiltiga datum, flera grupper och sidväxling.
- TypeScript, berörda ESLint-filer, regressionsprov för Workify/internöverföring/urval samt lokal produktionsbuild (webpack) godkända. Lokal Turbopack-build blockerades av worktree-länken till node_modules, inte av ändrad kod; Vercels ordinarie build ska verifieras före merge.
- Anonym åtkomst till v5 avstängd. Autentisering och `kpi.read` kontrolleras i privat Hub-funktion. Säkerhetsadvisorn gav inga fynd på den nya funktionen.
