-- User-confirmed links and monthly depreciation from the 2025/26 register.
-- Asset 139 is fully depreciated in this workbook. Exact workbook rates
-- retain fractional öre so aggregating months reconciles to the annual total.
do $migration$
declare
 tenant constant uuid := '944597b6-9c46-4bef-998d-f19e23c4245b';
 period_start constant date := '2025-09-01';
 period_end constant date := '2026-08-31';
 report_owner uuid;
 entry record;
 machine_id uuid;
 asset_reference text;
begin
 perform pg_advisory_xact_lock(hashtextextended('humla machine depreciation 2025/26',0));
 select s.requested_by into strict report_owner from private.hub_kpi_report_state s where s.tenant_id=tenant;
 for entry in select * from (values
  ('1009', 319, 'Anläggningsregister 25-26.xlsx · 1240 Bilar och Transporter rad 80 · tillgång 319', 17703.47222222),
  ('1031', 139, 'Anläggningsregister 25-26.xlsx · 1240 Bilar och Transporter rad 13 · tillgång 139', 0E-8),
  ('1040', 225, 'Anläggningsregister 25-26.xlsx · 1240 Bilar och Transporter rad 37 · tillgång 225', 16333.33333333),
  ('1046', 243, 'Anläggningsregister 25-26.xlsx · 1220 Inventarier & Verktyg rad 111 · tillgång 243', 17402.77777778),
  ('1048', 257, 'Anläggningsregister 25-26.xlsx · 1220 Inventarier & Verktyg rad 124 · tillgång 257', 23333.33333333),
  ('1053', 265, 'Anläggningsregister 25-26.xlsx · 1220 Inventarier & Verktyg rad 130 · tillgång 265', 20750.00000000),
  ('1054', 271, 'Anläggningsregister 25-26.xlsx · 1220 Inventarier & Verktyg rad 136 · tillgång 271', 2483.33333333),
  ('1057', 285, 'Anläggningsregister 25-26.xlsx · 1240 Bilar och Transporter rad 55 · tillgång 285', 7000.00000000),
  ('1058', 284, 'Anläggningsregister 25-26.xlsx · 1240 Bilar och Transporter rad 54 · tillgång 284', 17803.03030303),
  ('1059', 287, 'Anläggningsregister 25-26.xlsx · 1240 Bilar och Transporter rad 57 · tillgång 287', 17803.03030303),
  ('1062', 316, 'Anläggningsregister 25-26.xlsx · 1240 Bilar och Transporter rad 77 · tillgång 316', 10000.00000000),
  ('1063', 317, 'Anläggningsregister 25-26.xlsx · 1240 Bilar och Transporter rad 78 · tillgång 317', 16164.58333333),
  ('1064', 318, 'Anläggningsregister 25-26.xlsx · 1240 Bilar och Transporter rad 79 · tillgång 318', 7991.66666667),
  ('1066', 322, 'Anläggningsregister 25-26.xlsx · 1240 Bilar och Transporter rad 82 · tillgång 322', 6325.75757576),
  ('1067', 328, 'Anläggningsregister 25-26.xlsx · 1240 Bilar och Transporter rad 83 · tillgång 328', 6305.55555556)
 ) as confirmed(ao, asset_number, provenance, monthly_amount)
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
    and upper(trim(d.object_reference))=asset_reference and d.valid_from<=period_end
    and coalesce(d.valid_to,'infinity'::date)>=period_start
    and (d.source,d.monthly_depreciation,d.valid_from,d.valid_to)
      is distinct from (entry.provenance,entry.monthly_amount,period_start,period_end)
  ) then
   raise exception 'Overlapping depreciation period for %', asset_reference;
  end if;

  insert into public.kpi_asset_depreciation_periods
   (tenant_id,object_reference,source,monthly_depreciation,valid_from,valid_to)
  select tenant,asset_reference,entry.provenance,entry.monthly_amount,period_start,period_end
  where not exists (
   select 1 from public.kpi_asset_depreciation_periods d where d.tenant_id=tenant
    and upper(trim(d.object_reference))=asset_reference and d.valid_from=period_start
  );

  insert into public.kpi_dashboard_allocations
   (tenant_id,dimension,source,kind,reference_type,reference,target,valid_from,valid_to,reason,created_by)
  values
   (tenant,'project','Avskrivningsregister','cost','vehicle',asset_reference,entry.ao,period_start,period_end,entry.provenance,report_owner),
   (tenant,'cost_center','Avskrivningsregister','cost','vehicle',asset_reference,'10',period_start,period_end,entry.provenance,report_owner)
  on conflict (tenant_id,dimension,source,kind,reference_type,reference,valid_from) do nothing;
 end loop;
end $migration$;
