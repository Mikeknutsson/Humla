# Beständiga mappningar i Humla Hub

Varje verifierad manuell eller automatisk matchning ska kunna återanvändas av samtliga importvägar (NEXT, Workify, TransPA) och konsumerande moduler. Hubben äger regelverket; Dashboarden får inte skapa ett separat register.

## Befintliga resurser
- hub_identity_keys: verifierade identitetsalias.
- kpi_project_unit_mappings: datumstyrda projekt-/enhetskopplingar.
- hub_workify_driver_vehicle_rules: befintliga namn–fordon-regler.
- hub_driver_activity_assignments: datum- och tidsstyrd förar-/fordonsevidens.

## Krav på gemensam regelmodell
tenant_id, dimension (kst|project|vehicle), evidence_type, normalized_evidence_value, target_id, valid_from, valid_to, priority, confidence, status, origin, verified_by, verified_at, created_at, superseded_at, rule_version.
Unikhets-/konfliktkontroll per tenant, dimension, evidens och överlappande giltighetstid. Behörighetsstyrd ändring med audit trail. Käll-ID och transaktionsidentitet får aldrig bero på fördelningsregler.

## Prioritet
1. Verifierad explicit transaktionskoppling.
2. Bokförd KST eller exakt projektrelation.
3. Verifierad fordonsidentitet eller tidsöverlappande TransPA-koppling.
4. Bekräftad datumstyrd chaufförs-/arbetsledarregel.
5. Kalibrerad historisk sannolikhet.
Konflikt lämnar enbart berörd dimension ofördelad. Ingen giltig ekonomisk transaktion exkluderas p.g.a. mappningsbrist.

## Import och återanvändning
Läs regler centralt vid varje import och använd samma motor vid omklassificering. Återimport av helårsfiler ska inte skapa nya ekonomiska transaktioner eller återställa manuella fördelningar. Bekräftad korrigering sparas som transaktionsundantag eller återanvändbar regel efter uttryckligt val. Regeländringar får bara ändra fördelning, aldrig ekonomiskt totalbelopp.

## Testfall
1. Importera samma fil igen: 0 nya transaktioner, bibehållen mappning.
2. Importera överlappande period: endast nya källtransaktioner tillkommer.
3. Ändra chaufförens fordon en dag: undantag, inte global regel.
4. Byt arbetsledaransvar mitt i året: tidigare perioder oförändrade.
5. Saknad fordonskoppling: belopp kvar i total, fordon Ofördelat.
6. Samma mappningsregel används i KPI, Dashboard och Styrning & Ekonomi.
