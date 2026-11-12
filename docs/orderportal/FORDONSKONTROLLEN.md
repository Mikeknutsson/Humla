# Fordonskontrollen → Humla Orderportal

Implementerat 2026-11-12 på feature/separat-orderdashboard. Endast förhandsversion av transportportalen; inga KPI- eller faktureringsflöden ändrade.

## Verifierad källa

Autentiserade GET-anrop till befintlig anslutning, fleet_manager/v1:
- `/workorders`: `id`, `number`, `source.type/id/title`, `start`, nullable `end`, `title`, `description`, `location`, `completed_at`, `updated_at`, relaterade kontroll-/felrapporter. UTC-tider med explicit offset.
- `/inspections`: inställelsedatum under `expiration`, inte samma sak som bokat besök.
- `/tasks`: generella uppgifter, inte säkert tidsbokningar.

Första kompletta workorders-hämtningen: **579 arbetsorder**, **24 med start i oktober 2026**, 25 utan completed_at. 274 saknar source_object_id (bland annat maskiner av typen unit). Dessa syns med granskningsmarkering och matchas inte genom namn eller gissning. Framtida fordonsbokningar kontrollerade: DUN012 14 november, YPG213 19 november, CMO589/SPN03J 22 november, HGL39H 28 november. Maskinregistret är ännu inte anslutet till portalens fordonsval.

## Flöde

`private.orderportal_maintenance_tick()` körs varje minut med pg_cron. Efter en fullständig hämtning väntar den 15 minuter innan nästa börjar. En sida per tick; med nuvarande sex sidor tillkommer omkring sex minuters hämtningstid. Befintlig avstängning via hub_connection_sync_settings respekteras. Endast GET mot fast Fordonskontroll-domän; Vault-uppgifter hålls på servern.

Hela snapshoten samlas privat innan import. HTTP-/formatfel eller valideringsfel behåller föregående snapshot och visar synkfel. Max 100 sidor. Transaktionslås förhindrar överlappande pollning/import.

Befintlig `hub_sync_fordonskontroll_entities` återanvänds med WorkOrder/FordonskontrollWorkOrder. Kanoniska Hub-ID, externa referenser och hub_object_versions används. Repris ger samma identitet och ingen onödig historik. Ändrade källdata uppdaterar samma order med ny version.

Källorder är egna skrivskyddade underhållsorder (`source=fordonskontrollen`) i portalens orderlista/kalender. De läggs inte i hub_orderportal_orders, har inga intäktsrader, kan inte kopieras/redigeras/faktureras eller dras i kalendern. Lila kalenderkort med UNDERHÅLL och detaljdialog. Svenska tider i Europe/Stockholm. Tid, plats, instruktion och källa visas. Registreringsnummer visas men tilldelningen använder Hub-ID.

Befintlig kpi.manage krävs för API/RPC-läsning. Bakgrundstabell och tick är privata utan användaråtkomst. Privat tabell har RLS med avsiktlig default-deny utan policy; advisor-notisen om detta är väntad.

## Planeringsskydd

Kända intervall för ej utförda underhållsorder ingår i frontendkonflikter. Både vanlig ordersparning och drag-and-drop-planering kontrollerar överlapp på servern under samma organisationslås som importen. Vid ny verkstadsbokning som överlappar redan sparad transport kvarstår båda och konflikten visas. Artiklar/intäkter påverkas inte.

## Begränsningar

- Ingen starttid: ordern finns i listan men placeras inte på godtyckligt kalenderdatum.
- Ingen giltig sluttid: visas på startdagen med varning, ingen gissad varaktighet eller automatisk konfliktspärr för okänd sluttid.
- Saknad/otillgänglig kanonisk fordonskoppling: synlig granskningsflagga, ingen gissad tilldelning. Maskiner/unit kräver fortsatt registerkoppling.
- Saknas i senaste fullständiga snapshot: status Kontrollera källa. Försvinnande tolkas inte automatiskt som avbokning. Separat avbokningsfält är inte verifierat i API:t.
- Inställelsedatum från inspections och uppgifter från tasks skapar ännu inga kalenderposter. Bokade besiktningar finns i workorders.
- Portalens datumval är fortfarande oktober 2026 som standard; byt kalenderdatum för kommande bokningar.
- Frontend läser om från Hub varje minut när fliken är synlig. Ingen live-webhook.

## Verifiering

13 Node-tester: befintlig order/gruppering/planering och nya tester för vinter/sommartid, skrivskydd, konflikt, okänd tid och försvunnen källa.
SQL-rollbacktest `supabase/tests/orderportal_maintenance.sql`: idempotens, kanonisk tilldelning, ändringshistorik, svensk tid/överlapp, angränsande intervall, serverns sparspärr, försvunnen källa, organisationsisolering och rättigheter. Samtliga testskrivningar återställda.
Bygg med Next/TypeScript. Ingen visuell slutkontroll i autentiserad webbläsare: Vercel-inloggning blockerade tidigare kontrollen. Ingen ändring av faktiska Fordonskontroll-bokningar.
