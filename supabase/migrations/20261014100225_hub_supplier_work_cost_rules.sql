-- Reusable supplier evidence in the existing Hub/KPI compatibility rule adapter.
alter table public.kpi_dashboard_allocations drop constraint kpi_dashboard_allocations_reference_type_check;
alter table public.kpi_dashboard_allocations add constraint kpi_dashboard_allocations_reference_type_check
 check(reference_type in ('fact','project','vehicle','article','account','supplier'));
do $$declare sig text;d text;before text;begin
 foreach sig in array array['private.hub_kpi_financial_facts_v1(uuid,date,date)','private.hub_kpi_financial_month_facts_v1(uuid,date,date,integer[])']loop
  d:=pg_get_functiondef(sig::regprocedure);before:=d;
  d:=replace(d,$old$when 'account' then r.reference=f.acc else false end$old$,
   $new$when 'account' then r.reference=f.acc when 'supplier' then f.src='NEXT' and f.k='cost' and upper(trim(r.reference))=upper(trim(f.raw->>'Leverantör')) else false end$new$);
  d:=replace(d,$old$when 'fact' then 1 when 'project' then 2 when 'vehicle' then 3 when 'article' then 4 else 5 end$old$,
   $new$when 'fact' then 1 when 'supplier' then 2 when 'project' then 3 when 'vehicle' then 4 when 'article' then 5 else 6 end$new$);
  if d=before then raise exception 'Supplier adapter patch target changed: %',sig;end if;
  execute d;
 end loop;
end $$;
