-- Maintenance test caller sets task.tenant_id and a verified KPI reader subject.
do $$
declare t uuid:=current_setting('task.tenant_id')::uuid; a jsonb;b jsonb;c jsonb;n jsonb;
begin
 a:=public.hub_kpi_billing_balance_v1(t,2026,array[9],'{"cost_center":"30"}');
 b:=public.hub_kpi_billing_balance_v1(t,2026,array[10],'{"cost_center":"30"}');
 c:=public.hub_kpi_billing_balance_v1(t,2026,array[9,10,9],'{"cost_center":"30"}');
 if a->>'status'='ready' then
  assert (a->>'balance')::numeric=(a->>'invoiced')::numeric-(a->>'cost')::numeric,'Balance conservation';
  assert (a->>'balance')::numeric=(select sum((w->>'balance')::numeric)from jsonb_array_elements(a->'weeks')w),'Weekly conservation';
  assert (a->>'balance')::numeric=(a#>>'{weeks,-1,cumulative_balance}')::numeric,'Cumulative conservation';
 end if;
 assert (c->>'cost')::numeric=coalesce((a->>'cost')::numeric,0)+coalesce((b->>'cost')::numeric,0),'Distinct month scope';
 assert not (c->>'internal_included')::boolean,'External-only scope';
 n:=public.hub_kpi_billing_balance_v1(t,2026,array[9],'{"unit":"00000000-0000-0000-0000-000000000000"}');
 assert n->>'status'='no_data' and n->>'balance' is null,'Missing data must not appear as a positive zero';
 begin
  perform public.hub_kpi_billing_balance_v1(t,2026,array[9],'{"unsupported":"x"}');
  raise exception 'Invalid filter accepted';
 exception when raise_exception then
  if sqlerrm='Invalid filter accepted' then raise;end if;
 end;
end $$;
