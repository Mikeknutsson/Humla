-- Caller sets task.tenant_id and a verified KPI reader JWT subject.
do $$
declare t uuid:=current_setting('task.tenant_id')::uuid;r jsonb;
begin
 r:=public.hub_kpi_internal_summary_v1(t,2026,array[9],'{"cost_center":"30"}');
 assert (r->>'remaining')::numeric=(r->>'total')::numeric-(r->>'material')::numeric-(r->>'tipp_deponi')::numeric,'Remainder conservation';
 assert (r->>'remaining')::numeric=(r->>'transport')::numeric+(r->>'other')::numeric,'Transport and other included';
 assert (r->>'remaining_percent')::numeric=round((r->>'remaining')::numeric/nullif((r->>'revenue_basis')::numeric,0)*100,2),'Same KPI revenue denominator';
 r:=public.hub_kpi_internal_summary_v1(t,2026,array[9],'{"unit":"00000000-0000-0000-0000-000000000000"}');
 assert (r->>'remaining')::numeric=0 and r->>'remaining_percent' is null,'Zero denominator has no percentage';
end $$;
