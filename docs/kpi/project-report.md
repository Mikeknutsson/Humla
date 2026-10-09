# Projektuppföljning KST 10 och 60

Dashboard `/kpi/projekt` visar bokfört utfall exklusive moms: intäkter, kostnader, resultat, viktad marginal och personal. Projektledare, period och KST begränsar samtliga belopp. Textsökning begränsar endast projektlistan. CSV innehåller projekt och månadsutfall; detaljposter är uttryckligen endast aktuell sida.

Projekturvalet använder senaste bekräftade projektregister och kanoniska Hub-ID:n. Det ändrar inte historiska KST-kopplingar. Underlag från Projektöversikt(6).xlsx har registrerats med källa och versioner från 2026-10-09.

Bokförda projektposter hämtas från importerade NeXT-rader med Projektnr och Bokf datum. Personal ingår en gång i projektkostnaden. Löner kommer från NeXT för KST 10/60; Transport använder befintlig TransPA API-källa. Detta återinför inte löneprognoser i betalningsprognosens kostnader/netto.

Fordonsfördelning kan kvarstå när projektnummer, belopp och datum är säkra. Endast två befintliga feltyper för fordonsfördelning tolereras; andra fel undantas. Okategoriserade kostnader ingår och flaggas. Inga nya fordonskopplingar eller importstatusar skapas. NeXT-kontobeskrivningen Löner till kollektivanställda identifierar löner när kategoriregel saknas.

Interna bokförda NeXT-poster särredovisas som delar av totalsummorna. Workify-körningar hämtas först när användaren begär dem och kopplas till mottagande projekt via exakt registrerat projektnummer. De visas med granskningsstatus och läggs inte ovanpå NeXT eftersom dubbelbokföring annars kan uppstå. Kontrollpanelen äger kopplingarna.

Alla rapportanrop kräver aktiv medlemskap och kpi.read. RPC:n kontrollerar behörigheten i databasen. Anonyma anrop saknar execute. Ingen budget eller slutprognos räknas utan kalkyl och återstående arbete.

Gruppfiltret använder befintlig verksamhetsgrupp i bekräftat projektregister. Alla grupper är standard och Ingen grupp samlar tomma gruppvärden. Urvalet följer med i månadsval, projektdetaljer och CSV. v2-RPC:n filtrerar före beräkning; befintlig v1 är oförändrad.
