-- Caller sets task.tenant_id and a verified KPI reader subject.
do $$
declare t uuid:=current_setting('task.tenant_id')::uuid;r jsonb;expected numeric;g uuid;
begin
 select active_generation into g from private.hub_kpi_report_state where tenant_id=t;
 r:=private.hub_kpi_internal_overview_v1(t,2026,array[9],'{"cost_center":"20,30,40"}');
 select coalesce(sum(amount),0)into expected from private.hub_kpi_prepared_facts
 where tenant_id=t and generation_id=g and fiscal_year=2026 and extract(month from occurred_on)=9
 and cost_center in('20','30','40') and source='Workify' and kind='revenue'
 and lower(trim(original->>'Kundnamn'))='elleholms maskin ab' and original->>'Orderstatus'='Invoiced';
 assert (r->>'total')::numeric=expected,'Published invoice conservation';
 assert (r->>'total')::numeric=(r->>'material')::numeric+(r->>'tipp_deponi')::numeric+(r->>'transport')::numeric+(r->>'other')::numeric,'Category conservation';
 assert (r->>'review_included')::boolean,'Review rows must remain visible in financial total';
 select coalesce(sum(amount),0)into expected from private.hub_kpi_prepared_facts
 where tenant_id=t and generation_id=g and fiscal_year=2026 and extract(month from occurred_on)=9
 and cost_center in('20','30','40') and source='Workify' and kind='revenue'
 and lower(trim(original->>'Kundnamn'))='elleholms maskin ab' and original->>'Orderstatus' is distinct from 'Invoiced';
 assert (r->>'pending_amount')::numeric=expected,'Pending invoices remain separate';
 r:=private.hub_kpi_internal_overview_v1(t,2026,array[9],'{"unit":"00000000-0000-0000-0000-000000000000"}');
 assert (r->>'total')::numeric=0 and (r->>'rows')::integer=0,'Unit filter isolation';
end $$;
