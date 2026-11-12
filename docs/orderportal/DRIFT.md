# Driftövergång – påbörjad 2026-11-12

Databasgrunden är införd: hub_transport_orders och hub_transport_history, kanoniska TransportOrder-objekt, transaktionssäker nummerserie H-00000001 per organisation, idempotens och versionskontroll. Testtabellerna kvarstår separat. Ingen fakturaexport eller KPI-skrivning.

Sparandet kräver transport.orders.manage och kontrollerar kanoniska resurser, datum, rader, resursöverlapp och kända underhållsintervall. Testprisreferenser och testplats-ID avvisas. Transportbehörigheter är registrerade men inga användares behörigheter har utökats. read/assignments.read är reserverade; egna uppdrag kräver fortsatt personkoppling och avgränsad API/RLS.

Verifierat med rollbacktest: driftidentitet, nummerserie, idempotens, separat testdata, ändringshistorik och obehörig skrivning. Inga riktiga order skapade vid verifieringen.

Återstår innan driftstart: ansluta gränssnitt och API till driftflödet, produktionsprislistor, behörighetsadministration och chaufförernas egna uppdrag, fullständiga tester inklusive samtidighet och webbläsarkontroll. Befintlig förhandsversion är fortfarande testportal. Databasgrunden är inte en lanserad driftversion.
