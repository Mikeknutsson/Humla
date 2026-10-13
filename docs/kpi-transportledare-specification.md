# Humla KPI – Transportledare: personlig uppföljning

## Primär navigering: kostnadsenheter (beslut 2026-10-13)
- **Kostnadsenheten är startsidans och transportledarens primära objekt**, inte projektlistan.
- Default: Mina kostnadsenheter. Sekundärt filter: Mitt område. Projekt från NEXT används för koppling, filtrering och drilldown.
- En kostnadsenhet är den intäktsbringande ekonomiska enheten (t.ex. DFC86A), med kopplade släp, förare och delkostnader enligt Hub-regler.
- Huvudtabell per enhet: omsättning, kostnader, resultat, marginal %, målmarginal %, avvikelse procentenheter och SEK; kostnader per kategori samt transport/material/tippavgift separat.
- Enhetsdetalj: månadstrend, intäkt/timme, kostnad/mil, beläggning, debiteringsgrad, avvikelser, ordrar och källunderlag.
- Osäkra eller ofördelade belopp ska redovisas separat och avstämmas, aldrig tyst försvinna.
- Historiska ansvarstilldelningar gäller vid periodurval. Ingen dubbelsummering mellan perspektiven.
- Projektregistret (kostnadsställe 30 = Transport) är sekundär klassificeringskälla, inte ekonomisk källa.
- Implementation måste använda kanoniska Hub-enheter och Hub-aggregat. Saknas verifierad per-enhet-fördelning ska gränssnittet visa att underlag saknas, inte skapa egna fördelningar.

## Två separata ekonomiska perspektiv
- **Mitt område:** Alla arbetsorder tilldelade transportledarens område, oavsett utförande fordon.
- **Mina fordon:** Samtliga arbetsorder utförda av tilldelade ekonomiska enheter, oavsett orderns område.
- En arbetsorder kan synas i båda perspektiven. Summorna får aldrig adderas mellan perspektiven.
- Behörighet och tilldelning av område och enhet ska vara giltighetsdaterade, så att historiken inte flyttas vid ansvarsskifte.

## Uppföljningshierarki
Transportledare → perspektiv (område/fordon) → ekonomisk enhet → arbetsorder → orderrad → originalunderlag.
På varje nivå särredovisas **transport**, **material**, **tippavgifter** samt **ofördelat**. För varje kategori visas intäkt, kostnad, resultat och marginal.

## Målmarginaler
- Enhetsmål i `hub_kpi_unit_margin_targets` med giltighetsdatum.
- Exempel: DFC86A 4 %, ALD61D 10 %. Dessa är exempel, inte verkliga mål.
- Resultatmål i kronor = omsättning × målmarginal / 100.
- Avvikelse i kronor = verkligt resultat − resultatmål.
- Avvikelse i procentenheter = verklig marginal − målmarginal.
- Sammanvägt mål är omsättningsviktat. Vid måländring mitt i en period beräknas varje delperiod för sig.
- Ingen målberäkning för nollomsättning utan explicit hantering av resultat och ej definierad marginal.

## Arbetsorder – klickbar detalj
Visa orderidentitet, datum, kund, projekt, område, utförande enhet, förare och status.
Visa separat:
1. Intäktsrader från Workify, med artikel, kvantitet, á-pris, belopp och intäktstyp.
2. Direkta orderkostnader från NEXT och andra källor, med originalreferens.
3. Spårbart fördelade kostnader med fördelningsnyckel och säkerhetsnivå.
4. Ofördelade kostnader, separat från orderresultatet.
5. Avstämning mellan ordersumma och underlag.

Kombinerade artiklar (material inklusive transport) får inte godtyckligt delas; kräv verifierad fördelningsregel eller redovisa kombinerat.
En order kan ha flera utförande fordon. Fördela bara där verifierat underlag finns.

## Integrationsgräns mot Work
Denna gren innehåller enbart KPI-specifikation och målmodell. Work ansvarar för den gemensamma Hub-matchningen, historik, import och ekonomisk transaktionsidentitet.
Ingen separat matchningsmotor får skapas i Dashboard.

## Acceptanskriterier
- Två perspektiv visar korrekta, självständiga totalsummor.
- Varje synligt belopp kan följas till arbetsorder och originalrad.
- Transport, material och tippavgifter kan jämföras separat.
- Enhetsmål kan ändras framåt utan att historiska mål skrivs över.
- Ett fordon kan byta transportledare utan att tidigare månader omklassificeras.
- Inga ekonomiska transaktioner dupliceras i summering.
- Osäkra kopplingar redovisas separat.
