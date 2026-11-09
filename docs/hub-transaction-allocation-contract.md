# Humla Hub – ekonomisk giltighet och sannolikhetsbaserad fördelning

## Grundregel
Transaktionens existens, ekonomiska inkludering, dublettidentitet och organisatoriska fördelning är fyra separata dimensioner. Saknat fordon, projekt, KST, chaufför eller arbetsledare får aldrig ensamt göra en unik ekonomisk transaktion ogiltig. Dubbletter eller redan bokförda kompletterande underlag ska däremot inte räknas två gånger.

## Matchningsordning
1. Verifierat käll-ID och källrad identifierar ekonomisk transaktion (separat från fördelning).
2. Bokfört KST och giltig projektrelation ger auktoritativ fördelning.
3. Registreringsnummer/fordons-ID på order ger direkt fordonskoppling.
4. TransPA:s tidsintervall för chaufför och fordon på aktuellt datum.
5. Andra verifierade Workify-order samma dag.
6. Datumstyrda chaufför–fordon-regler, arbetsledaransvar, kund, artikel, leverantör, referens och historisk körfrekvens.
7. Vid motstridiga signaler lämnas enbart osäker dimension ofördelad.

## Statusar
economic_status: included | excluded_duplicate | excluded_accounted_elsewhere | invalid_economic_data.
allocation_status per dimension: verified | inferred | provisional | unallocated.
Varje beslut sparar regelversion, evidens, tidsintervall och konfidens. Sannolikhet måste kalibreras mot manuellt verifierade utfall och får inte presenteras som statistiskt sannolik utan sådan kalibrering.

## Invarianta tester
- Samma helårsfil återimporterad två gånger ger noll nya ekonomiska transaktioner andra gången.
- Överlappande importer behåller två legitima identiska rader med skilda verifierade käll-ID.
- Fordons-/KST-omfördelning ändrar inte företagets total.
- Okänd KST visas Ofördelat, inte automatiskt KST20/30.
- NEXT-bokförd intäkt och kompletterande fakturaunderlag ger en ekonomisk händelse.
- Historiska originalrader skrivs inte över; korrigeringar revisionsloggas.
- Tenantisolering och behörighet kontrolleras i varje skrivväg.

## Införande
Inför först read-only jämförelser mot september 2026 och kontrollera differenser per källa och KST. Aktivera sedan en ny versionsstyrd fördelningsmotor med återställbar utrullning. Ändra inte gamla is_valid-flaggor i bulk och publicera inte ekonomiska totaler som avstämda före kontroll mot NEXT.
