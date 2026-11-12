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

## Fördjupad UI-kartläggning 2026-11-11

Läst via inloggad Workify-webbläsare. Artikel-, person-, fordons- och orderformulär öppnades för inspektion och stängdes utan att spara. Inga skarpa order eller register ändrades. Antal registerposter ändrades under asynkron inläsning; mellanvärden används inte som verifierade totalsiffror.

### Artiklar och prislistor — verifierat
- Artikellista: artikelnummer, namn, enhet, standardkostnad, vägbar, tidsartikel, index och prislistans pris. Sökning, visa borttagna, prislistval, export samt kontroller för skapa/redigera/radera finns.
- Artikelkort (DMT Bil): nummer, namn, enhet, vägbar/tidsartikel, index, produktgrupp, kalkylkostnad, EAN, branschartikelnummer, avfallskod, omräkningsfaktor till rapporterad vikt i kg samt standardkommentar.
- Produktgrupper i väljaren: Verkstad, Maskiner, Externa Avsättningar, Uthyrningsartiklar, Försäljning Grusmaterial, Avräkningsartiklar, Tippavgifter Pukavik, Försäljning Pukavik och Lastbilar.
- Separat prislistflik med kod/namn, beskrivning och kopiera/redigera/radera-kontroller. STD är visuellt låst. Kundspecifika och interna listor förekommer, exempelvis SEVAB, KEVAB, STENA och ELLEHINTERN.
- Prislistornas detaljredigering, prioritet och automatiska prisval är inte verifierade. Klick på prislistnamn gav inte ett verifierbart detaljresultat.

### Personer — verifierat
- Lista under Mitt företag med förnamn, efternamn, e-post, telefon, användartyp, standardfordon, regelverk, färgkod och bokningsbar resurs. Aktiv/inaktiv/alla-filter och inaktiveringskontroller finns.
- Personkort: namn, kontaktuppgifter, anställnings-ID, lönetyp (månad/timme), endast avvikelserapportering, användartyp, standardfordon, färgkod och bokningsbar resurs. Fält för nytt lösenord finns men användes inte.
- Roller som visas: Operations manager, Planner, Driver, Finance och Driver +. Rollernas faktiska behörighetsmatris har inte testats.
- Användarkonto och bokningsbar resurs är skilda begrepp. Listan innehåller även samlings-/externa resurser och är inte en säker förteckning över fysiska anställda.
- Personuppgifter kopierades inte till denna dokumentation. Standardkopplingar är aktuella registerinställningar, inte bevis för historiska körningar.

### Fordon och objekt — verifierat
- Lista: namn, beskrivning, regnr, standardchaufför, VIN, kostnadsställe, typ och färg. Aktiv/inaktiv-filter.
- Öppnat hjullastarkort: namn/regnr, beskrivning, VIN, modell, fabrikat, fordonstyp, standardchaufför, färg, bränsle, motortyp, förbrukning per sträcka/timme och CO2-val, kostnadsställe, skopvolym, maskinvikt och lyftkapacitet.
- Underhåll och Dokument visas som avstängda flikar med uppmaning att kontakta försäljning. Dessa räknas inte som aktiva funktioner i det granskade kontot.
- Resurstaggar, uthyrningskategorier, kostnadsställen, produktgrupper och sparade mottagare visas som separata registersektioner. Detaljfunktionerna i dessa är inte testade.

### Order 45547 — verifierad detaljstruktur
- Överst: ordernummer, Skicka, Skriv ut, Redigera, Upprepa, Kopiera, Radera. Åtgärdernas genomförande testades inte.
- Märkning, objektnummer, externt dokumentnummer och projekt samt stegindikator Planering → Pågående → Granskning → Fakturering.
- Visuell översikt med färgad status/radvärde, start/slut, planerare, tilldelad person och fordon. Separat händelsepanel med kommentarsfilter.
- Detaljer: titel/instruktion, kund, kundreferens och kontakt. Separata sektioner för karta/platser, vägningar, artiklar, fakturaanteckning, filer och händelser.
- Artikelrader: person, datum, artikel, antal, enhet, à-pris, summa, kommentar samt redigera/radera. Ordern innehåller transport, material och tippavgifter.
- Filsektionen har systemdokument (följesedel/vågkvitto) och uppladdade bilder. Filer öppnades eller laddades inte ned i denna genomgång.
- Redigeringsformulär grupperas i Grunduppgifter, Detaljer, Resurser och planering samt Tillägg. Där finns kund/projekt/titel/instruktion, märkning/objektnummer/extern projektreferens/era och våra referenser, datum/tider, omvänd moms, kundportal, miljörapport och dokument-/leveransval. Ingen skickfunktion användes.

### Konsekvenser för Humla — föreslagna förbättringar
- Skilj visuell orderöversikt från redigerbara fält; visa tydliga resursikoner och samlad status/radvärde.
- Eget artikelregister och separata prislistor, inte enbart textförslag på orderraden. Rikare register kräver verifierad datakoppling till Hubben; saknade metadata ska inte hittas på.
- Separera personer, fordon, kund och projekt i registervyer. Koppla via kanoniska Hub-ID.
- Skilj resursfärg (vem/vad) från statusfärg (var i flödet). Standardchaufför/fordon får inte skrivas över till historiska order automatiskt.
- Bilagor, vägningar, prisavtal och flerroller återstår i Humla; Workify-funktioner ovan är inte ett påstående om implementerad Humla-funktionalitet.

### Kalender och Skapa order — fördjupning samma dag

- Kalendern granskades i vecka 46 (9–15 november), den period som öppnades i kontot. Oktober är fortsatt Humlas testperiod.
- Tidslinje: resurser som rader, datum som kolumner, grupper för ej tilldelade, chaufförer och fordonstyper. Dagens kolumn markeras och flera dagars order visas som sammanhängande block.
- Hela bokningsblock har färgad bakgrund och innehåller tid, ordernummer/titel, kund och plats när motsvarande visningsval är på.
- Växling från Status till Resource genomfördes: samma chaufförs bokningar fick samma färg som resursens färgprick. Ej tilldelade blev röda i resursläget. Läget återställdes till Status.
- Orange bokning 45718 öppnades och statusen Unassigned verifierades. Grönmint och mörk turkos förekom på andra kort men full färg–status-matris är inte verifierad. Humlas övriga statusfärger är egna, inte påstådda exakta Workify-färger.
- Statusmenyn visar Ordered, Confirmed, Unassigned, Assigned, In progress, On hold, Done, Reported, [Ready for] Invoicing och Invoiced. Inget statusval genomfördes.
- Agenda öppnades och visade veckodagar som kolumner och klockslag vertikalt; därefter återställdes Timeline. Dag/vecka/månad finns som periodval. Månadsvyn testades inte.
- Visningsval: kund, platser, ej tilldelade, inaktiva resurser, fordonstyp, fordon/objekt och personer; sökbart resursurval och komprimerade platser. Drag-and-drop testades inte, eftersom det skulle kunna ändra skarpa bokningar.
- Kalenderns plusknapp öppnade Skapa order. Formuläret har mintgrön rubrikrad och tydligt inramade sektioner: Grunduppgifter, Detaljer, Platser, Resurser och planering, Artiklar, Tillägg, Filer samt miljö-/dokumentval.
- Kund, titel och slutdatum markerades som obligatoriska. Vår referens var förifylld med inloggad användare.
- Platsdelen: Lägg till plats, favoritplats samt visa från/till på faktura respektive följesedel.
- Resursdelen: start-/slutdatum, start-/sluttid, sökbart fordonsval med namn och registreringsnummer, chaufför och omvänd moms. Fordonsväljaren öppnades men ingen resurs valdes.
- Lägg till artikel var avstängd med uttrycklig hjälptext att kund och slutdatum måste väljas först. Artikelinmatning i ny order testades därför inte i denna genomgång.
- Filer: filval och kommentar. Tillägg: kundportal, miljörapport, följesedel/fakturaunderlag, e-post/BEAst 4.0 och mottagare.
- Formuläret stängdes med Avbryt och bekräftelsen Stäng utan att spara. Ingen order skapades.

### Implementerat efter fördjupningen

- Mjukare Nunito Sans, statusflikar med urvalsantal och konsekventa statusfärger.
- Visuell ordersammanfattning med status, radvärde, tider, chaufför och fordon; grupperade fält i redigering.
- Humlas planering har fullfärgade orderkort, läsbar statustext även i resursfärgläge, statuslegend, sökning, statusfilter, kund-/platsvisning, dag/sjudagarsval och separat ej-tilldelad-lista för vald resurstyp.
- Resursfärgerna i Humla härleds deterministiskt från resursnyckeln för visning. De är inte importerade Workify-färger eller administrativt sparade val, och unik färg för varje resurs garanteras inte.
- Humlas kalender är fortsatt en resurs-/dagtabell: timplacerad agenda, månad, drag-and-drop och full Workify-statusmodell återstår. Registerfunktioner, fler orderfält och dokumentflöden ovan är kartlagda men inte fullt implementerade.

## Ombyggnad 2026-11-12

- Smal navigation, svart text, Humlas gula markeringar och tät statusfärgad ordertabell som standard. Kortvy finns kvar, med kort på mobil.
- Ej tilldelade order visas i samma datumrutnät som resurserna.
- Sökbara val från befintliga Humla-ID för kund, projekt, fordon, förare och artiklar. Registerval skapar inga nya kund-/artikelidentiteter.
- Orderformulär: kund/projekt, rubrik, större instruktion, kontaktuppgifter, platser, planering/resurser, referenser, kommentarer och artiklar.
- Kontaktuppgifter är orderbundna fält, inte ett färdigt kundkontaktregister. Adresslänken öppnar Google Maps; den är inte inbyggd autocomplete.
- Artikelregistret har en egen sökbar läsvy. Materialrader kan spara hämtplats, mottagningsplats och separat inköpspris i testorderns befintliga JSON-payload och versionshistorik. Platser är fritext tills ett gemensamt platsregister kopplats in.
- Försäljningspriser märks servermässigt som manuella testpriser. Automatiska STD-, kund-, projekt- och platspriser är INTE implementerade. De ska inte härledas från intäktsimporter eller ersättas av kopierade artiklar.
- Köpkostnad ingår inte i orderns försäljningssumma. Vald artikel kontrolleras mot organisationens aktiva Hub-register via order-API:t.
- Inga ändringar i KPI-kod, beräkningar, skarpa Workify-order eller fakturaintegrationer. Inga nya databastabeller eller migreringar i denna revision.

Verifiering: Next-produktionsbygge och modelltester. Visuell browser-QA försöktes med syntetisk lokal fixture men kunde inte köras: Chromium stoppades av miljön (socket Operation not permitted). Sparande/återöppning av de nya fälten i en inloggad liveförhandsversion återstår att verifiera. Fullständig Workify-kartläggning är fortsatt ofärdig efter utgången inloggning.

## Prisflöde – 2026-11-12, fortsättning

Implementerat i testportalen:
- Egen Prislistor-vy: skapa grundprislista (en per organisation), kundavtal, projektavtal och namngivna täkter/tippplatser. Allt lagras i Hubben. Prislistor och platser får kanoniska testobjekt-ID, artiklar/kunder/projekt återanvänder befintliga Hub-ID.
- Prisrader med artikel, enhet, giltighetsdatum, valfri hämt-/mottagningsplats, försäljningspris och separat valfritt inköpspris.
- Hub-funktionen väljer projekt > kund > grundpris, sedan högsta platsspecificitet inom den nivån. Datum och enhet måste matcha exakt. Saknad plats vid möjliga platspriser kräver platsval. Lika rang ger konflikt i stället för godtyckligt val.
- Orderradens Hämta avtalspris är ett uttryckligt val. Spara kontrollerar register-ID, avtalsvillkor och pris på nytt i databasen. Prisradens ID och prisvillkor sparas som snapshot med orderhistoriken. Inköpspris påverkar inte försäljningssumman.
- Priser arkiveras med tid och användar-ID; ersättningspris kan registreras efteråt. Befintliga order kan behålla arkiverat pris, nya order får inte använda det. Historik visas med Visa arkiverade.
- Prisregister är tomt från början: Workify-prislistor och ekonomins befintliga materialinköpspriser har INTE importerats eller automatiskt mappats. Inga antagna affärspriser har skapats.

Verifiering: produktionsbygge, sex modelltester samt transaktionella databastester av prioritering, platskrav, datum, överlapp, konflikt, prissnapshot, inköp/försäljning, ändrat projekt, arkivering, bevarat orderpris och tenantbehörighet. Befintlig ordertestsvit med versionskontroll, historik och faktureringsspärr körd igen. Alla testskrivningar rullades tillbaka. Säkerhetsrådgivaren gav inga orderportal-specifika anmärkningar.

Begränsningar: inloggad browser-QA återstår; visuell verifiering är inte genomförd. Automatisk prisimport, rabatt-/indexmodeller, littrabaserade avtal, olika prislistor per kund med valbart avtal, masskopiering och Google Maps-autocomplete återstår. Samtidiga lika prioriterade kund-/projektlistor kräver att användaren korrigerar överlappande priser. Testplatser är uttryckligen separata från ett framtida skarpt platsregister och ska mappas vid produktionssättning.

## Mörkgrå navigation och aktiv planering – 2026-11-12

- Navigationens bakgrund och mörka segmentknappar ändrade från nästan svart till mörkgrå (#34383e). Svart innehållstext och gula aktiva val behålls.
- Aktiva Humla-testorder (Utkast, Planerad, Pågående) kan dras mellan kalenderdagar och kanoniskt identifierade fordons-/förarrader. Ett granskningsformulär öppnas före sparande. Knappen Planera / tilldela ger motsvarande funktion på mobil och med tangentbord.
- Valet Visa lediga resurser visar även registerresurser utan bokning i aktuellt urval. Ej tilldelad finns som möjlig målrad. Kalenderfiltret kan dölja uppdrag; konflikter kontrolleras ändå mot alla aktiva Humla-testorder i organisationen.
- Flytt av ett flerdagarsuppdrag utgår från den dag som greps och bevarar hela uppdragets datumlängd och lokala klockslag. Datum och priser på artikelrader ändras inte automatiskt; detta framgår i formuläret.
- Planering sparas i Hubben med befintlig versionskontroll och full orderhistorik. Uppslag av fordons-/förarnamn sker från kanoniska Hub-ID på serversidan.
- Alla ordinarie testordersparningar och planeringsändringar använder nu ett gemensamt organisationslås före konfliktkontroll. Överlapp för samma fordon eller förare blockeras. Intilliggande tidsintervall tillåts. Utförda/avbrutna/faktureringsklara order ingår inte i konfliktkontrollen.
- Workify-importer är skrivskyddade och används inte för att garantera skarp resurskapacitet. Kalenderflytt påverkar inte KPI, Workify eller fakturering.

Verifiering: Next-produktionsbygge, åtta modelltester och databasens rollback-test för fordon/förare, vanlig ordersparning, angränsande perioder, flerdagarsflytt, avregistrering av resurs, gammal version, ändringshistorik, oförändrade artikelrader, slutförd order och obehörig användare. Inloggad visuell kontroll och faktiska drag-/touchinteraktioner är ännu inte verifierade i webbläsare.

Kalenderceller har även Ny order med förvald dag och den valda resurstypens Hub-ID. Formuläret kompletteras med kund/uppdrag före sparande.
