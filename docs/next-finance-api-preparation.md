# NeXT ekonomi-API: förberedelse i Humla Hub

Status: **förberett, inte anslutet**. Version 1, endast shadow/staging.
Ingen API-hämtning, cron, hemlighet, ny databasbehörighet eller automatisk
aktivering skapas av denna ändring. Befintliga importer/KPI-regler är oförändrade.
Den befintliga `next-project-sync` är en separat testkoppling och får inte
förväxlas med en verifierad ekonomisynk.

## Kod och anslutningspunkter

- `src/lib/hub/next-finance.ts`: Hub-kontrakt, normalisering, kanonisk identitet,
  sidvis shadow-inläsning, validering, vattenmärke och felhantering.
- `NextFinanceTransport.readPage`: framtida read-only NeXT-adapter. **Kontraktets
  fältnamn är Humlas interna format, inte ett påstående om NeXT:s API-schema.**
- `NextFinanceStageSink`: framtida permanent lagring för inaktiva generationer,
  originalpayload, revisionshistorik och checkpoint. Kräver implementation och
  integrationstest före faktisk anslutning; minnes-/testsink får inte användas live.
- `resolveProject`: använd bekräftade `hub_identity_keys` + `hub_objects`, avgränsat
  till tenant och anslutning. NeXT:s API-ID och filernas projektnummer kan vara
  olika identiteter för samma Humla-objekt. Lägg inte API-ID i interna relationer.
- `GET /api/hub/next-finance/readiness`: autentiserad, tenant-avgränsad status för
  `kpi.manage`. Ingen POST/aktivering och inga hemligheter i svaret.
- `/integrationer/ekonomi`: visar ärlig förberedelsestatus och återstående steg.

## Innan NeXT kan anslutas

1. Verifiera leverantörens aktuella dokumentation och behörigheter: projekt
   inklusive avslutade/inaktiva, bokföringsrader, lönekostnader och fakturor.
   Gör endpoint-, fält-, tecken-, valuta-, bokföringsdatum- och pagineringsmapping
   i transportadaptern, inte i Dashboard. Tillåt bara verifierade HTTPS-hostar,
   inga redirects med Authorization till andra hostar; sätt timeout och begränsade
   retries för 429/5xx. Ekonomi-adaptern är läsande, inte en NeXT-writeback.
2. Spara credentials i Hubbens Vault/server-side-referenser, inte i publik
   configuration, `NEXT_PUBLIC_*`, klientkod eller loggar. Auktorisera worker
   och tenant/connection före varje körning; inga hårdkodade företags-ID:n.
3. Implementera sink med tenant-isolering, anslutningslås, inaktiv run/generation,
   unik sourceKey + payloadHash, råpayload och revisionshistorik. Gör completion
   och checkpoint atomiskt. Fel lämnar staged data inaktiv; checkpoint oförändrad.
   Testa samtidiga körningar, replay, ändrade rader och återstart efter sidfel.
4. Hämta hela projektregistret, även historiskt. Saknade/ambigua identiteter
   stannar i granskning. Borttagna rader blir tombstones för granskning, aldrig
   automatisk förlust av finansiell historik. Partial sync får inte radera rader
   som inte råkade komma med. Vattenmärke sparas vid körningens START; använd
   en verifierad överlappningsperiod vid nästa API-läsning för sena ändringar.
5. Stäm av API mot nuvarande filer i Hubben. Authoritativt bokföringsrad-ID behövs;
   fakturanummer, belopp, datum eller projektnamn ensamma bevisar inte dubblett.
   Fil/API utan säker gemensam radidentitet får inte blandas i aktiva KPI-fakta.
   Kund-/leverantörsfakturor är avstämnings-/betalningsunderlag, inte extra
   bokförd intäkt/kostnad. Lön är en kostnadskategori, inte en andra bokföringsrad.
6. API och filer måste väljas exklusivt per källa, period och mått i Hubbens
   generationsbyggare. Behåll dagens regler: Transportlön TransPA, andra KST
   NeXT; Workify externa intäkter för 20/30; interna kostnader avräknas mot
   bokfört 4600; Elleholms Stena är extern. Hantera krediter med originaltecken.
7. Jämför projekt/månad/KST/källa mot filbaserat resultat. Avvikelse ska kunna
   härledas till en originalrad. Begär separat godkännande före aktivering.
   Då behövs en explicit publiceringsfunktion och rollback till föregående
   aktiva generation. `runNextFinanceShadow` kan ALDRIG publicera KPI.

## Test

`node --test scripts/test-next-finance.mjs`

Testar avstängda spärrar, tenant-scopade nycklar, stabil hash/revision,
kanoniska identiteter, historiska projekt, kredittecken, belopp/date-validation,
paginering, upprepade cursors, storage failure och sekretess i felkoder.
Transport och sink används med fixtures; detta är **inte** ett genomfört
integrationstest mot NeXT eller en live databas-sink.
