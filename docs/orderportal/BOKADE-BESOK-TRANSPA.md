# Bokade fordonsbesök och kombinerad kalender

Urvalet kräver en tidszonsangiven starttid på en WorkOrder och antingen plats eller besöksrelaterad rubrik (besiktning, verkstad, Scania, service, Kbes, bokad, besök). Rena felrapporter och poster utan start visas inte som order. Samma begränsning används i databasens konfliktkontroll. Källobjekten bevaras för spårbarhet.

API-underlaget saknar separat verifierad bokningsflagga. Urvalet är därför en försiktig klassificering av bokningsuppgifter, inte bekräftelse från verkstaden. En felrapport med plats och tid kan ingå som bokat besök; kontrollera källbokningen vid tveksamhet.

Magenta markerar besöken i kalender, kort och lista, även vid färgläggning per resurs. Egen vy Bokade fordonsbesök öppnar alla datum och kan sedan filtreras. Åtgärder, att-göra, kategorier och tillhörande felrapporter visas i instruktionerna när källan har dem. Ingen separat felrapport blir en order.

Kalenderns Chaufförer + fordon visar chaufförsrader först och fordonsrader därefter. Samma order är två resursreferenser, inte två order. Dragning använder målraden för att ändra rätt resurstyp; orderantalet räknar varje order en gång.

# TransPA – verifierad möjlighet, inte aktiverad överföring

Officiell Swagger https://api.mytranspa.com/doc/openapi/swaggerui/ listar POST /v1/timeReports och PUT /v1/timeReports/{id}. Integration kräver godkänd skrivåtkomst enligt https://transpa.se/kunskapsbank/aktivera-transpa-public-api-integration.

Nästa implementation bör vara en separat arbetstidsrapport med kanonisk person/fordon, start/slut, rast och aktiviteter, användargranskning och idempotent exportstatus. Orderns debiterbara timmar får inte automatiskt bli lönegrundande tid. Befintliga TransPA-rapporter måste avstämmas innan skapande för att undvika dubblering. Exakta fält, behörigheter och sandbox-skrivning återstår att verifiera. Ingen TransPA-skrivning har utförts.
