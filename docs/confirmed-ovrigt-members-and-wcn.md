# Bekräftad gruppering och WCN517

Beslut av Mike 2026-10-15: SOU57P och MDE75S (angivna som SOU57/MDE755) ska ingå i Övrigt. WCN517 ska delas på Bygg & Anläggning.

Två bekräftade `reports_in`-relationer mellan kanoniska ekonomiska Humla-enheter och Övrigt sparas i befintliga `hub_object_relations`, med godkännare, datum och giltighet från 2025-09-01, samma start som de befintliga källkopplingarna. Fordonens egna identiteter och medlemsperioder behålls. Rapportfakta behåller källfordon, projekt, kostnadsställe, kategori, datum och belopp. Här ingår även redan fördelade kostnadsandelar som tillhör dessa två enheter. Bekräftad gruppering skiljs från osäker matchning i spårbarhetsinformationen.

WCN517 läggs till som källa i den befintliga regeln ”Bygg & Anläggning – gemensamma släp/jiggar”, med samma åtta valda kanoniska mottagare och undantag för LMT31J/CXS239. Antalet regler är fortsatt tolv. Befintlig datumlogik gäller: PUJ55R:s första enhetsperiod börjar 2026-09-07. Sju giltiga mottagare före detta datum får lika andel (1/7); därefter åtta (1/8). Inga historiska medlemskap hittas på. Den sista andelen tar öresavrundningen, så varje ursprunglig kostnad bevaras exakt. Granskningsloggen sparar regelsnapshot och ursprunglig kostnad.

Motorn ersätter ursprungsrader med andelar, aldrig ett extra kostnadspåslag. Detalj- och kompaktunderlag uppdateras tillsammans. Vid varje kommande publicering körs kostnadsregeln och den bekräftade rapportgrupperingen på nytt från samma Hub-konfiguration. Grupperade källor ommatchas inte som om de vore okända identiteter.

Operationsskriptet kontrollerar finansiella summor per månad, kostnadsställe, kategori och intäkt/kostnad före och efter. Regressionstest täcker källidentiteter, säker klassificering, upprepning utan ändringar, WCN-fördelning och avsaknad av kvarvarande originalkostnad, samt nekad obehörig åtkomst.
