-- Additional 2025/26 register links. Approved probable matches are marked in the source.
-- Use only monthly depreciation columns. For the sold asset 174 this excludes its disposal.
-- Assets 101 and 140 are fully depreciated and retain a zero-cost link.
do $migration$
declare
 tenant constant uuid := '944597b6-9c46-4bef-998d-f19e23c4245b';
 report_owner uuid;
 entry record;
 machine_id uuid;
 asset_reference text;
begin
 perform pg_advisory_xact_lock(hashtextextended('humla machine depreciation 2025/26',0));
 select s.requested_by into strict report_owner
 from private.hub_kpi_report_state s where s.tenant_id=tenant;
 for entry in select * from (values
  ('1006', 140, '10', 'Anläggningsregister 25-26.xlsx · 1240 Bilar och Transporter rad 18 · tillgång 140 · sannolik: modell', 0E-8, date '2025-09-01', date '2026-08-31'),
  ('1011', 101, '10', 'Anläggningsregister 25-26.xlsx · 1240 Bilar och Transporter rad 8 · tillgång 101 · sannolik: modell och uppskattad inköpsordning', 0E-8, date '2025-09-01', date '2026-08-31'),
  ('1023', 174, '20', 'Anläggningsregister 25-26.xlsx · 1240 Bilar och Transporter rad 28 · tillgång 174 · sannolik: modell och markerad såld', 15991.66666667, date '2025-09-01', date '2026-02-28'),
  ('1039', 177, '10', 'Anläggningsregister 25-26.xlsx · 1240 Bilar och Transporter rad 23 · tillgång 177 · sannolik: modell och uppskattad inköpsordning', 18116.66666667, date '2025-09-01', date '2026-08-31'),
  ('1039', 253, '10', 'Anläggningsregister 25-26.xlsx · 1220 Inventarier & Verktyg rad 120 · tillgång 253 · AO-märkt tillbehör', 255.93333333, date '2025-09-01', date '2026-08-31'),
  ('1041', 226, '10', 'Anläggningsregister 25-26.xlsx · 1240 Bilar och Transporter rad 42 · tillgång 226 · sannolik: fabrikat och maskintyp', 2458.33333333, date '2025-09-01', date '2026-08-31'),
  ('1042', 224, '20', 'Anläggningsregister 25-26.xlsx · 1240 Bilar och Transporter rad 36 · tillgång 224 · sannolik: modellfamilj L60', 8784.72222222, date '2025-09-01', date '2026-08-31'),
  ('1050', 254, '10', 'Anläggningsregister 25-26.xlsx · 1220 Inventarier & Verktyg rad 121 · tillgång 254 · AO-märkt tillbehör', 250.25000000, date '2025-09-01', date '2026-08-31'),
  ('1050', 261, '10', 'Anläggningsregister 25-26.xlsx · 1220 Inventarier & Verktyg rad 126 · tillgång 261 · sannolik: modell och inköpsdatum före AO-märkt skopa', 18181.81818182, date '2025-09-01', date '2026-08-31'),
  ('1050', 369, '10', 'Anläggningsregister 25-26.xlsx · 1240 Bilar och Transporter rad 103 · tillgång 369 · AO-märkt tillbehör', 203.00000000, date '2025-09-01', date '2026-08-31'),
  ('1052', 222, '10', 'Anläggningsregister 25-26.xlsx · 1240 Bilar och Transporter rad 34 · tillgång 222 · sannolik: modell och uppskattad inköpsordning', 20833.33333333, date '2025-09-01', date '2026-08-31'),
  ('1052', 252, '10', 'Anläggningsregister 25-26.xlsx · 1220 Inventarier & Verktyg rad 119 · tillgång 252 · AO-märkt tillbehör', 255.93333333, date '2025-09-01', date '2026-08-31'),
  ('1055', 277, '10', 'Anläggningsregister 25-26.xlsx · 1240 Bilar och Transporter rad 52 · tillgång 277 · sannolik: modell och kvarvarande PW148 efter AO 1050', 20075.75757576, date '2025-09-01', date '2026-08-31'),
  ('1060', 301, '10', 'Anläggningsregister 25-26.xlsx · 1240 Bilar och Transporter rad 64 · tillgång 301 · matchning mot modell eller AO i registret', 20284.90972222, date '2025-09-01', date '2026-08-31'),
  ('1061', 264, '10', 'Anläggningsregister 25-26.xlsx · 1220 Inventarier & Verktyg rad 129 · tillgång 264 · sannolik: modell och uppskattad inköpsordning', 20075.75757576, date '2025-09-01', date '2026-08-31'),
  ('1062', 362, '10', 'Anläggningsregister 25-26.xlsx · 1220 Inventarier & Verktyg rad 171 · tillgång 362 · AO-märkt tillbehör', 2782.14285714, date '2025-09-01', date '2026-08-31'),
  ('1069', 386, '10', 'Anläggningsregister 25-26.xlsx · 1240 Bilar och Transporter rad 110 · tillgång 386 · matchning mot modell eller AO i registret', 23863.63636364, date '2026-01-01', date '2026-08-31'),
  ('1071', 335, '10', 'Anläggningsregister 25-26.xlsx · 1240 Bilar och Transporter rad 87 · tillgång 335 · matchning mot modell eller AO i registret', 15801.00000000, date '2025-09-01', date '2026-08-31'),
  ('1072', 372, '10', 'Anläggningsregister 25-26.xlsx · 1240 Bilar och Transporter rad 89 · tillgång 372 · matchning mot modell eller AO i registret', 4563.00000000, date '2025-09-01', date '2026-08-31'),
  ('1073', 344, '10', 'Anläggningsregister 25-26.xlsx · 1240 Bilar och Transporter rad 91 · tillgång 344 · matchning mot modell eller AO i registret', 10893.00000000, date '2025-09-01', date '2026-08-31'),
  ('1076', 352, '10', 'Anläggningsregister 25-26.xlsx · 1240 Bilar och Transporter rad 93 · tillgång 352 · matchning mot modell eller AO i registret', 10038.00000000, date '2025-09-01', date '2026-08-31'),
  ('1078', 354, '10', 'Anläggningsregister 25-26.xlsx · 1240 Bilar och Transporter rad 95 · tillgång 354 · matchning mot modell eller AO i registret', 8283.00000000, date '2025-09-01', date '2026-08-31'),
  ('1080', 359, '10', 'Anläggningsregister 25-26.xlsx · 1240 Bilar och Transporter rad 98 · tillgång 359 · matchning mot modell eller AO i registret', 7002.00000000, date '2025-09-01', date '2026-08-31'),
  ('1081', 377, '20', 'Anläggningsregister 25-26.xlsx · 1240 Bilar och Transporter rad 106 · tillgång 377 · matchning mot modell eller AO i registret', 10166.66666667, date '2025-10-01', date '2026-08-31'),
  ('1083', 392, '60', 'Anläggningsregister 25-26.xlsx · 1240 Bilar och Transporter rad 112 · tillgång 392 · matchning mot modell eller AO i registret', 10416.66666667, date '2026-03-01', date '2026-08-31'),
  ('1084', 385, '10', 'Anläggningsregister 25-26.xlsx · 1240 Bilar och Transporter rad 109 · tillgång 385 · matchning mot modell eller AO i registret', 8020.83333333, date '2026-01-01', date '2026-08-31'),
  ('1085', 398, '10', 'Anläggningsregister 25-26.xlsx · 1240 Bilar och Transporter rad 116 · tillgång 398 · matchning mot modell eller AO i registret', 29965.27777778, date '2026-04-01', date '2026-08-31'),
  ('1086', 387, '60', 'Anläggningsregister 25-26.xlsx · 1240 Bilar och Transporter rad 111 · tillgång 387 · matchning mot modell eller AO i registret', 16742.42424242, date '2026-03-01', date '2026-08-31'),
  ('1087', 403, '10', 'Anläggningsregister 25-26.xlsx · 1240 Bilar och Transporter rad 120 · tillgång 403 · matchning mot modell eller AO i registret', 14923.48484848, date '2026-06-01', date '2026-08-31'),
  ('1089', 399, '10', 'Anläggningsregister 25-26.xlsx · 1240 Bilar och Transporter rad 117 · tillgång 399 · matchning mot modell eller AO i registret', 21863.63636364, date '2026-04-01', date '2026-08-31'),
  ('1091', 402, '10', 'Anläggningsregister 25-26.xlsx · 1240 Bilar och Transporter rad 119 · tillgång 402 · matchning mot modell eller AO i registret', 12416.66666667, date '2026-06-01', date '2026-08-31')
 ) as matched(ao, asset_number, kst, provenance, monthly_amount, starts_on, ends_on)
 loop
  select k.object_id into strict machine_id
  from public.hub_identity_keys k
  where k.tenant_id=tenant and k.object_type='Project'
    and k.identity_type='next_project_number' and k.identity_value=entry.ao and k.confidence=1
    and exists (
     select 1 from public.hub_identity_keys a
     where a.tenant_id=tenant and a.object_id=k.object_id
       and a.object_type='Project' and a.identity_type='next_machine_article_number'
       and a.confidence=1
    );

  asset_reference := 'AO ' || entry.ao || ' TILLGÅNG ' || entry.asset_number;
  if exists (
   select 1 from public.hub_identity_keys k where k.tenant_id=tenant
    and k.identity_type='asset_depreciation_reference'
    and k.identity_value like 'AO % TILLGÅNG ' || entry.asset_number
    and k.identity_value<>asset_reference
  ) then
   raise exception 'Asset % is already linked to a different machine', entry.asset_number;
  end if;
  insert into public.hub_identity_keys (tenant_id,object_id,object_type,identity_type,identity_value,confidence)
  values (tenant,machine_id,'Project','asset_depreciation_reference',asset_reference,1)
  on conflict (tenant_id,identity_type,identity_value) do nothing;

  if not exists (
   select 1 from public.hub_identity_keys k where k.tenant_id=tenant
    and k.identity_type='asset_depreciation_reference' and k.identity_value=asset_reference
    and k.object_id=machine_id and k.object_type='Project' and k.confidence=1
  ) then
   raise exception 'Conflicting asset identity for %', asset_reference;
  end if;

  if exists (
   select 1 from public.kpi_asset_depreciation_periods d where d.tenant_id=tenant
    and upper(trim(d.object_reference))=asset_reference and d.valid_from<=entry.ends_on
    and coalesce(d.valid_to,'infinity'::date)>=entry.starts_on
    and (d.source,d.monthly_depreciation,d.valid_from,d.valid_to)
      is distinct from (entry.provenance,entry.monthly_amount,entry.starts_on,entry.ends_on)
  ) then
   raise exception 'Overlapping depreciation period for %', asset_reference;
  end if;

  insert into public.kpi_asset_depreciation_periods
   (tenant_id,object_reference,source,monthly_depreciation,valid_from,valid_to)
  select tenant,asset_reference,entry.provenance,entry.monthly_amount,entry.starts_on,entry.ends_on
  where not exists (
   select 1 from public.kpi_asset_depreciation_periods d where d.tenant_id=tenant
    and upper(trim(d.object_reference))=asset_reference and d.valid_from=entry.starts_on
  );

  insert into public.kpi_dashboard_allocations
   (tenant_id,dimension,source,kind,reference_type,reference,target,valid_from,valid_to,reason,created_by)
  values
   (tenant,'project','Avskrivningsregister','cost','vehicle',asset_reference,entry.ao,entry.starts_on,entry.ends_on,entry.provenance,report_owner),
   (tenant,'cost_center','Avskrivningsregister','cost','vehicle',asset_reference,entry.kst,entry.starts_on,entry.ends_on,entry.provenance,report_owner)
  on conflict (tenant_id,dimension,source,kind,reference_type,reference,valid_from) do nothing;
 end loop;
end $migration$;
