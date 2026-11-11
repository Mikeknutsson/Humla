# Humla Orderportal – kartläggning och testleverans

Kartlagd 2026-11-11 genom inloggad Workify-webbläsare, enbart läsning.
Gren: feature/separat-orderdashboard. Ingen ändring av main eller KPI-kod.

## Vad som verifierats i Workify

| Del | Observerat | Verifieringsnivå |
|---|---|---|
| Orderlista | Ordernummer, titel, kund, värde, start/slut, skapare, tilldelad, fakturanotering, rutt, senaste aktivitet, status, märkning, projekt | Visat i listan |
| Sökning | Fritext; avancerat ordernummer, hyra, kund, artikel, chaufför, fordon, plats i rutt, status, märkning, objektnummer, kontakt, vår/er referens, titel, projektnummer, projektledare | Filterpanelen öppnad; oktober och fritext använda |
| Snabbfilter | Alla, idag, imorgon, denna vecka; Planning/In progress/Review/Invoicing; datumintervall; visa raderade; farligt avfall | Kontroller finns, destruktiva val inte använda |
| Sidindelning | 20 order på första sidan, sidknappar; orderdetalj visar position 3/642, 20/642 och 9/642 | Observerat, 20 är inte periodens totalantal |
| Orderfält | Nummer, märkning, objekt, externt dokumentnummer, projekt, start/slut och tid, planerare, chaufför, fordon, rubrik, instruktion, kund, referens, kontakt | Lästa i tre order |
| Artiklar | Användare, datum, artikel, antal, enhet, à-pris, summa, kommentar; redigerings-/raderingskontroller | Lästa, inga ändringar gjorda |
| Platser | Flera ruttplatser, favoritplats, karta, ruttoptimering, visa på faktura/följesedel | Kontroller observerade, ej aktiverade |
| Vägningar | Datum, station, vågsedel, fraktion/artikel, typ, in/ut/nettovikt, synkroniseringsknapp | Tom tabell och kontroller observerade |
| Bilagor | Filnamn, användare, datum, kommentar; inkludera utskrift/faktura/kundportal; systemföljesedel/vågkvitto | Filer och inställningar observerade |
| Historik | Händelser, skapad av/tid, filtrera kommentarer | Lästa; kommentar-knappen var inaktiverad i kontot |
| Skapa, kopiera, upprepa, redigera, skicka, skriva ut, statusändring | Kontroller finns | Inte genomförda; får inte markeras funktionstestade |
| Kalender | Dag/vecka/månad; Timeline/Agenda; färgkodning status/resurs; filter kund, plats, ej tilldelad, inaktiva resurser, fordonstyp, fordon, användare | Veckokalender öppnad, kontrollalternativ lästa |
| Drag-and-drop och konfliktvarning | Inte testade eftersom de kan ändra skarp planering | Ej verifierade |
| Faktureringsunderlag/orderbekräftelse | Menyer för fakturering, skicka och skriva ut finns | Fullständigt flöde och mottagare ej verifierade |

Den lämnade orderlänken innehöll en aktiv fritextsökning på 12118. Den togs bort innan oktoberperioden granskades.

## Oktoberavstämning

- `kpi_import_rows`: 1 111 Workify-intäktsrader med artikeldatum 1–31 oktober; 392 olika ordernummer; 1 111 unika fingerprints; 12 ogiltigmarkerade rader.
- Importer 19/10, 26/10, 2/11 och 9/11. Dessa är inte en livekoppling.
- Workify: 642 order i valt datumfilter med alla angivna statusar. Ingen slutsats att skillnaden är felimport: listan och intäktsunderlaget har olika omfattning och datumdefinitioner.
- För de 392 ordernumren hämtas totalt 1 116 tillgängliga importerade rader, inklusive fem rader utanför oktober, så att en order inte kapas av periodfiltret. Fullständig order kan ändå inte garanteras.
- Sex order har flera importbatcher: 45069, 45144, 45187, 45242, 45244, 45389. Alla rader behålls med granskningsflagga. Samma fingerprint inom samma tenant räknas en gång; olika förekomster med identiskt belopp får inte slås ihop.
- Summa råa oktoberintäktsrader: 4 177 082,30 kr. Inte en avstämd faktureringsbalans.

| Order | Typ | Hubben | Workify | Resultat |
|---|---|---:|---:|---|
| 45576 | Maskinflytt + hyra, 2 rader | 2 810,00 | 2 810,00 | Belopp stämmer. Hubstatus ReadyForInvoicing, Workify Invoiced (externt dokument 38493). |
| 45507 | Stena-insamling, 8 rader | 9 962,00 | 9 962,00 | Belopp stämmer, Ready for Invoicing. Artikeldatum både 29 och 30/10 trots planerat datum 30/10. |
| 45547 | Inhyrt ekipage, matjord, betong/asfalt, 4 rader | 8 144,70 | 8 244,70 | Workifys transportartikel/pris har ändrats: 2,5 h × 1 290 i stället för 1 250. Skillnad 100 kr. Explicit granskningsflagga i testadaptern. |

## Levererad testfunktionalitet

- Egen navigation och inloggningssida under /orderportal. Gemensam befintlig autentisering, egen layout/CSS som bara aktiveras på portalens sidor.
- Sökning, källa/status/kund/fordonsfilter, artikeldatum eller överlappande planperiod, sortering och 25 order per sida.
- Skrivskyddade importerade order; full lista av tillgängliga källrader, originalfält, rad-ID/fingerprint, importtid och kvalitetsvarningar.
- Skapa/kopiera/redigera testorder, artikelrader, status, kanonisk kund/projekt/fordon/person, instruktion, interna och externa anteckningar. Ingen utsändning av anteckningar.
- Databaspersistens, atomiskt sparande, idempotent skapande, versionskonflikter, oföränderlig ändringshistorik.
- Dag och 7-dagars resurskalender, fordon eller chaufför, ej tilldelat, öppna order och byt tid/resurs. Överlappningsvarning mellan aktiva testorder.
- Gemensamt resurs-, kund- och projektregister, skrivskyddat. Artikelregister ger benämningsförslag; prisavtal är inte kopplade.
- Kontrollvy för utförda/faktureringsklara testorder. Databasens is_test får inte vara false; inga faktureringsendpoints eller exportkopplingar.

## Arkitektur och behörighet

Importpresentationen är en läsprojektion med källreferens, inte ett nytt intäktsregister. Kopior får nytt kanoniskt `hub_objects`-ID med typen `TestTransportOrder`. Resurstilldelning använder befintliga kanoniska objekt-ID. Inga gissade namnkopplingar sparas. Importerade projekt saknar verifierad kanonisk koppling och måste väljas när kopian redigeras.

`hub_orderportal_orders` + `hub_orderportal_history` har RLS och enbart SELECT för autentiserade klienter. Sparande sker genom en snäv privat funktion med auth.uid(), aktiv tenant och kpi.manage-kontroll, typ-/tenantkontroll av referenser, serverberäknade radsummor och atomisk historik. Publika RPC är SECURITY INVOKER. Versionen är avsiktligt begränsad till befintliga administratörer; ingen ny behörighet har delats ut.

Ingen localStorage för affärsdata. Inga ändringar av befintliga KPI-regler, importer, kostnadsfördelningar eller faktureringsmotor. Databastester återställs med ROLLBACK.

## Återstår före ersättning av Workify

Fullständig/live orderimport, nya behörigheter för transportledare, verkligt orderregister utanför test, bilagehantering, orderbekräftelser, återkommande uppdrag, drag-and-drop, validerad skarp konfliktkontroll, släp/maskiner, prisavtal, ändringsbara artikel-/statusregister samt fakturaunderlag/export och Fortnox-integration. Ny testversion ersätter ännu inte Workify.

## Genomförda kontroller

- `npm run build`: godkänd, inklusive TypeScript och samtliga app-rutter.
- Fem automatiska modelltester: stabil radidentitet, identiska legitima rader, tenantseparering, saknade ordernummer, granskningsflaggor, resurskonflikter och validering.
- Databastest med ROLLBACK: skapande, uppdatering, serverberäknat belopp, idempotens, två historikversioner, versionskonflikt, spärrad Fakturerad-status, full läsning över 1 000 rader, RLS och nekad obehörig skrivning. Alla godkända.
- KPI-underlagets antal kvarstår: 1 111 oktoberrader / 392 ordernummer. Inga testorder kvar efter databastestet.
- Lokal visuell QA kunde inte genomföras: preview-servern startade men Work-webbläsaren fick ERR_CONNECTION_REFUSED mot den tilldelade adressen. Dator/mobil och fullständigt inloggat användarflöde behöver därför verifieras på den publicerade förhandsversionen.
- Endast portalens egna filer, dokumentation, tester och nya databasobjekt ändrade. Produktion/main publiceras inte.
