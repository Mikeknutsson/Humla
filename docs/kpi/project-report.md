# Projektuppföljning

Dashboard `/kpi/projekt` har KST 10, 20, 30, 40, 50, 60 och 90. Alla kostnadsställen är standard. Verksamhetsgrupper väljs med kryssrutor; inga kryss betyder alla grupper. Period, KST, projektledare och flera grupper filtrerar före beräkning i Hubben och följer med i månadslänkar, projektdetaljer och CSV. Textsökning begränsar endast projektlistan.

Urvalet använder senaste bekräftade projektregister med kanoniska Hub-ID:n. Det ändrar inte historiska KST-kopplingar. v1 och v2-RPC:er bevaras för äldre konsumenter; v3 utökar urval och källor.

NeXT ger projektkostnader och intäkter för KST 10, 40, 50, 60 och 90. Externa Workify-intäkter från den aktiva Hub-generationen ersätter NeXT-intäkter för KST 20/30. TransPA-personalkostnader för KST 30 hämtas från samma befintliga Hub-underlag och beräkningsmotor. De är en tidsbaserad kostnadsberäkning, inte bokförda löner. För övriga KST används NeXT-personal.

TransPA och Workify kopplas via befintliga bekräftade Hub-identitetsnycklar och kanoniska objekt, aldrig nya gissningar. Endast entydiga objekt med ett aktuellt registerprojekt och matchande KST inkluderas. NeXT-löner, pensionsförsäkringspremier, arbetsgivaravgifter och sociala avgifter för KST 30 undantas på uttrycklig kontobeskrivning så befintlig TransPA-schablon inte läggs ovanpå löneunderlaget. Övriga personalkostnader såsom utbildning och arbetskläder behålls.

Personalkostnaden ingår en gång i totalkostnad och resultat. Ingen löneprognos återinförs i betalningsprognosens kostnader/netto. Interna NeXT-poster är delar av totalsummorna. Interna Workify-körningar visas separat för avstämning och läggs inte ovanpå bokföringen. Kontrollpanelen äger kopplingarna.

Fordonsfördelning kan kvarstå när NeXT-projekt, belopp och datum är säkra. Endast befintliga två feltyper för fordonsfördelning tolereras; andra fel undantas. Okategoriserade kostnader ingår och flaggas. Inga nya identiteter eller importstatusar skapas.

Aktivt medlemskap och kpi.read krävs. Anon saknar execute. CSV innehåller projekt och månadsutfall; detaljposter är endast aktuell sida. Budget och slutprognos kräver kalkyl och återstående arbete.

Hub-källor begränsas till kostnadsställen som finns i urvalet. Kanonisk identitet löses en gång per distinkt källreferens. Importkoppling använder UUID-index. Tilldelade Hub-belopp avrundas en gång till ören före projekt/månadsberäkning; undantagna Workify/TransPA-rader redovisas när kopplingen inte är entydig.

Gruppalternativen hämtas från projekt med intäkter eller kostnader inom valt KST, period och projektledare. Aktiva gruppkryss och detaljprojekt begränsar inte vilka övriga grupper som kan väljas. Vid byte av KST skickas formuläret direkt och tidigare grupp-/projektval rensas. Perioder utan belopp visar ett tomt gruppval; kvarvarande val utan belopp anges separat och kan rensas.
