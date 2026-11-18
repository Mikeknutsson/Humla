-- Carry forward the August 2026 rates for the previously mapped machine assets.
-- The August closing value caps the projection. Each asset has at most one partial final month.
do $migration$
declare
 tenant uuid;
 report_owner uuid;
 starts_on constant date := date '2026-09-01';
 entry record;
 full_months int;
 remaining numeric;
begin
 select s.tenant_id,s.requested_by into strict tenant,report_owner
 from private.hub_kpi_report_state s
 where exists(select 1 from public.hub_identity_keys k where k.tenant_id=s.tenant_id
  and k.identity_type='asset_depreciation_reference' and k.identity_value='AO 1009 TILLGÅNG 319');
 perform pg_advisory_xact_lock(hashtextextended('machine-depreciation-plan:'||tenant::text,0));
 for entry in select * from (values
  ('AO 1009 TILLGÅNG 319', '1009', '10', 17703.47, 1996951.67, 2549300.00, 'Anläggningsregister 25-26.xlsx · 1240 Bilar och Transporter rad 80 · tillgång 319 · prognos från september 2026'),
  ('AO 1039 TILLGÅNG 177', '1039', '10', 18116.67, 470278.00, 2174000.00, 'Anläggningsregister 25-26.xlsx · 1240 Bilar och Transporter rad 23 · tillgång 177 · prognos från september 2026'),
  ('AO 1039 TILLGÅNG 253', '1039', '10', 255.93, 11244.60, 30712.00, 'Anläggningsregister 25-26.xlsx · 1220 Inventarier & Verktyg rad 120 · tillgång 253 · prognos från september 2026'),
  ('AO 1040 TILLGÅNG 225', '1040', '10', 16333.33, 610556.00, 1960000.00, 'Anläggningsregister 25-26.xlsx · 1240 Bilar och Transporter rad 37 · tillgång 225 · prognos från september 2026'),
  ('AO 1041 TILLGÅNG 226', '1041', '10', 2458.33, 95406.00, 295000.00, 'Anläggningsregister 25-26.xlsx · 1240 Bilar och Transporter rad 42 · tillgång 226 · prognos från september 2026'),
  ('AO 1042 TILLGÅNG 224', '1042', '20', 8784.72, 436224.67, 1265000.00, 'Anläggningsregister 25-26.xlsx · 1240 Bilar och Transporter rad 36 · tillgång 224 · prognos från september 2026'),
  ('AO 1046 TILLGÅNG 243', '1046', '10', 17402.78, 1398487.33, 2506000.00, 'Anläggningsregister 25-26.xlsx · 1220 Inventarier & Verktyg rad 111 · tillgång 243 · prognos från september 2026'),
  ('AO 1048 TILLGÅNG 257', '1048', '10', 23333.33, 1492556.00, 2800000.00, 'Anläggningsregister 25-26.xlsx · 1220 Inventarier & Verktyg rad 124 · tillgång 257 · prognos från september 2026'),
  ('AO 1050 TILLGÅNG 254', '1050', '10', 250.25, 10994.00, 30030.00, 'Anläggningsregister 25-26.xlsx · 1220 Inventarier & Verktyg rad 121 · tillgång 254 · prognos från september 2026'),
  ('AO 1050 TILLGÅNG 261', '1050', '10', 18181.82, 1402969.36, 2400000.00, 'Anläggningsregister 25-26.xlsx · 1220 Inventarier & Verktyg rad 126 · tillgång 261 · prognos från september 2026'),
  ('AO 1050 TILLGÅNG 369', '1050', '10', 203.00, 228829.63, 233700.00, 'Anläggningsregister 25-26.xlsx · 1240 Bilar och Transporter rad 103 · tillgång 369 · prognos från september 2026'),
  ('AO 1052 TILLGÅNG 222', '1052', '10', 20833.33, 719246.00, 2500000.00, 'Anläggningsregister 25-26.xlsx · 1240 Bilar och Transporter rad 34 · tillgång 222 · prognos från september 2026'),
  ('AO 1052 TILLGÅNG 252', '1052', '10', 255.93, 11244.60, 30712.00, 'Anläggningsregister 25-26.xlsx · 1220 Inventarier & Verktyg rad 119 · tillgång 252 · prognos från september 2026'),
  ('AO 1053 TILLGÅNG 265', '1053', '10', 20750.00, 1451808.00, 2490000.00, 'Anläggningsregister 25-26.xlsx · 1220 Inventarier & Verktyg rad 130 · tillgång 265 · prognos från september 2026'),
  ('AO 1054 TILLGÅNG 271', '1054', '10', 2483.33, 153140.00, 298000.00, 'Anläggningsregister 25-26.xlsx · 1220 Inventarier & Verktyg rad 136 · tillgång 271 · prognos från september 2026'),
  ('AO 1055 TILLGÅNG 277', '1055', '10', 20075.76, 1638181.82, 2650000.00, 'Anläggningsregister 25-26.xlsx · 1240 Bilar och Transporter rad 52 · tillgång 277 · prognos från september 2026'),
  ('AO 1057 TILLGÅNG 285', '1057', '10', 7000.00, 497000.00, 840000.00, 'Anläggningsregister 25-26.xlsx · 1240 Bilar och Transporter rad 55 · tillgång 285 · prognos från september 2026'),
  ('AO 1058 TILLGÅNG 284', '1058', '10', 17803.03, 1531060.27, 2350000.00, 'Anläggningsregister 25-26.xlsx · 1240 Bilar och Transporter rad 54 · tillgång 284 · prognos från september 2026'),
  ('AO 1059 TILLGÅNG 287', '1059', '10', 17803.03, 1550644.27, 2350000.00, 'Anläggningsregister 25-26.xlsx · 1240 Bilar och Transporter rad 57 · tillgång 287 · prognos från september 2026'),
  ('AO 1060 TILLGÅNG 301', '1060', '10', 20284.91, 2181464.17, 2921027.00, 'Anläggningsregister 25-26.xlsx · 1240 Bilar och Transporter rad 64 · tillgång 301 · prognos från september 2026'),
  ('AO 1061 TILLGÅNG 264', '1061', '10', 20075.76, 1571195.82, 2650000.00, 'Anläggningsregister 25-26.xlsx · 1220 Inventarier & Verktyg rad 129 · tillgång 264 · prognos från september 2026'),
  ('AO 1062 TILLGÅNG 316', '1062', '10', 10000.00, 900000.00, 1200000.00, 'Anläggningsregister 25-26.xlsx · 1240 Bilar och Transporter rad 77 · tillgång 316 · prognos från september 2026'),
  ('AO 1062 TILLGÅNG 362', '1062', '10', 2782.14, 186403.57, 233700.00, 'Anläggningsregister 25-26.xlsx · 1220 Inventarier & Verktyg rad 171 · tillgång 362 · prognos från september 2026'),
  ('AO 1063 TILLGÅNG 317', '1063', '10', 16164.58, 1456425.00, 1939750.00, 'Anläggningsregister 25-26.xlsx · 1240 Bilar och Transporter rad 78 · tillgång 317 · prognos från september 2026'),
  ('AO 1064 TILLGÅNG 318', '1064', '10', 7991.67, 719250.00, 959000.00, 'Anläggningsregister 25-26.xlsx · 1240 Bilar och Transporter rad 79 · tillgång 318 · prognos från september 2026'),
  ('AO 1066 TILLGÅNG 322', '1066', '10', 6325.76, 655348.82, 835000.00, 'Anläggningsregister 25-26.xlsx · 1240 Bilar och Transporter rad 82 · tillgång 322 · prognos från september 2026'),
  ('AO 1067 TILLGÅNG 328', '1067', '10', 6305.56, 733966.67, 908000.00, 'Anläggningsregister 25-26.xlsx · 1240 Bilar och Transporter rad 83 · tillgång 328 · prognos från september 2026'),
  ('AO 1069 TILLGÅNG 386', '1069', '10', 23863.64, 2959090.91, 3150000.00, 'Anläggningsregister 25-26.xlsx · 1240 Bilar och Transporter rad 110 · tillgång 386 · prognos från september 2026'),
  ('AO 1071 TILLGÅNG 335', '1071', '10', 15801.00, 2401774.00, 2781000.00, 'Anläggningsregister 25-26.xlsx · 1240 Bilar och Transporter rad 87 · tillgång 335 · prognos från september 2026'),
  ('AO 1072 TILLGÅNG 372', '1072', '10', 4563.00, 620494.00, 730000.00, 'Anläggningsregister 25-26.xlsx · 1240 Bilar och Transporter rad 89 · tillgång 372 · prognos från september 2026'),
  ('AO 1073 TILLGÅNG 344', '1073', '10', 10893.00, 2203564.30, 2465000.00, 'Anläggningsregister 25-26.xlsx · 1240 Bilar och Transporter rad 91 · tillgång 344 · prognos från september 2026'),
  ('AO 1076 TILLGÅNG 352', '1076', '10', 10038.00, 2409089.45, 2650000.00, 'Anläggningsregister 25-26.xlsx · 1240 Bilar och Transporter rad 93 · tillgång 352 · prognos från september 2026'),
  ('AO 1078 TILLGÅNG 354', '1078', '10', 8283.00, 2425210.06, 2624000.00, 'Anläggningsregister 25-26.xlsx · 1240 Bilar och Transporter rad 95 · tillgång 354 · prognos från september 2026'),
  ('AO 1080 TILLGÅNG 359', '1080', '10', 7002.00, 2856948.22, 3025000.00, 'Anläggningsregister 25-26.xlsx · 1240 Bilar och Transporter rad 98 · tillgång 359 · prognos från september 2026'),
  ('AO 1081 TILLGÅNG 377', '1081', '20', 10166.67, 1108166.67, 1220000.00, 'Anläggningsregister 25-26.xlsx · 1240 Bilar och Transporter rad 106 · tillgång 377 · prognos från september 2026'),
  ('AO 1083 TILLGÅNG 392', '1083', '60', 10416.67, 1187500.00, 1250000.00, 'Anläggningsregister 25-26.xlsx · 1240 Bilar och Transporter rad 112 · tillgång 392 · prognos från september 2026'),
  ('AO 1084 TILLGÅNG 385', '1084', '10', 8020.83, 705833.33, 770000.00, 'Anläggningsregister 25-26.xlsx · 1240 Bilar och Transporter rad 109 · tillgång 385 · prognos från september 2026'),
  ('AO 1085 TILLGÅNG 398', '1085', '10', 29965.28, 4165173.61, 4315000.00, 'Anläggningsregister 25-26.xlsx · 1240 Bilar och Transporter rad 116 · tillgång 398 · prognos från september 2026'),
  ('AO 1086 TILLGÅNG 387', '1086', '60', 16742.42, 2109545.45, 2210000.00, 'Anläggningsregister 25-26.xlsx · 1240 Bilar och Transporter rad 111 · tillgång 387 · prognos från september 2026'),
  ('AO 1087 TILLGÅNG 403', '1087', '10', 14923.48, 1925129.55, 1969900.00, 'Anläggningsregister 25-26.xlsx · 1240 Bilar och Transporter rad 120 · tillgång 403 · prognos från september 2026'),
  ('AO 1089 TILLGÅNG 399', '1089', '10', 21863.64, 2776681.82, 2886000.00, 'Anläggningsregister 25-26.xlsx · 1240 Bilar och Transporter rad 117 · tillgång 399 · prognos från september 2026'),
  ('AO 1091 TILLGÅNG 402', '1091', '10', 12416.67, 1452750.00, 1490000.00, 'Anläggningsregister 25-26.xlsx · 1240 Bilar och Transporter rad 119 · tillgång 402 · prognos från september 2026')
 ) as assets(reference,project,cost_center,monthly,closing_book,depreciation_basis,source)
 loop
  if not exists (
   select 1 from public.kpi_asset_depreciation_periods d
   where d.tenant_id=tenant and d.object_reference=entry.reference
    and d.valid_to=starts_on-1 and round(d.monthly_depreciation,2)=entry.monthly
  ) or not exists (
   select 1 from public.hub_identity_keys a
   join public.hub_identity_keys p on p.tenant_id=a.tenant_id and p.object_id=a.object_id
   where a.tenant_id=tenant and a.identity_type='asset_depreciation_reference' and a.identity_value=entry.reference and a.confidence=1
    and p.identity_type='next_project_number' and p.identity_value=entry.project and p.confidence=1
  ) then
   raise exception 'August depreciation basis or machine mapping changed: %',entry.reference;
  end if;
  full_months:=floor(entry.closing_book/entry.monthly);
  remaining:=entry.closing_book-full_months*entry.monthly;
  insert into public.kpi_asset_depreciation_periods
   (tenant_id,object_reference,source,purchase_value,book_value_start,residual_value,monthly_depreciation,valid_from,valid_to)
  select tenant,entry.reference,entry.source,entry.depreciation_basis,entry.closing_book,0,p.amount,p.from_date,p.to_date
  from (values
   (entry.monthly,starts_on,(starts_on+make_interval(months=>full_months))::date-1),
   (remaining,(starts_on+make_interval(months=>full_months))::date,(starts_on+make_interval(months=>full_months+1))::date-1)
  ) p(amount,from_date,to_date)
  where p.amount>0 and p.from_date<=p.to_date
   and not exists(select 1 from public.kpi_asset_depreciation_periods d where d.tenant_id=tenant
    and d.object_reference=entry.reference and d.source=entry.source and d.valid_from=p.from_date and d.valid_to=p.to_date
    and d.monthly_depreciation=p.amount);

  if exists(
   select 1 from public.kpi_asset_depreciation_periods a join public.kpi_asset_depreciation_periods b
    on b.tenant_id=a.tenant_id and b.object_reference=a.object_reference and a.id<>b.id
    and b.valid_from<=coalesce(a.valid_to,'infinity'::date) and coalesce(b.valid_to,'infinity'::date)>=a.valid_from
   where a.tenant_id=tenant and a.object_reference=entry.reference and a.source=entry.source
  ) then raise exception 'Overlapping depreciation plans: %',entry.reference; end if;

  insert into public.kpi_dashboard_allocations
   (tenant_id,dimension,source,kind,reference_type,reference,target,valid_from,valid_to,reason,created_by)
  values
   (tenant,'project','Avskrivningsregister','cost','vehicle',entry.reference,entry.project,starts_on,
    (starts_on+make_interval(months=>full_months+case when remaining>0 then 1 else 0 end))::date-1,entry.source,report_owner),
   (tenant,'cost_center','Avskrivningsregister','cost','vehicle',entry.reference,entry.cost_center,starts_on,
    (starts_on+make_interval(months=>full_months+case when remaining>0 then 1 else 0 end))::date-1,entry.source,report_owner)
  on conflict (tenant_id,dimension,source,kind,reference_type,reference,valid_from) do nothing;
 end loop;
end $migration$;
