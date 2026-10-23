-- Caller sets task.tenant_id and a verified manager JWT subject. Rollback only.
begin;
do $$
declare t uuid:=current_setting('task.tenant_id')::uuid;g uuid;e record;r jsonb;f jsonb;fid text;
begin
 select active_generation into g from private.hub_kpi_report_state where tenant_id=t;
 select * into strict e from private.hub_kpi_provisional_supplier_costs where tenant_id=t and month_start='2026-09-01' and supplier_name='Erik Ivarsson Enskild firma';
 fid:='provisional-supplier-cost:'||e.id::text;
 assert (select count(*)=1 from private.hub_kpi_prepared_facts where tenant_id=t and generation_id=g and fact_id=fid);
 assert (select count(*)=1 from private.hub_kpi_prepared_display_facts where tenant_id=t and generation_id=g and fact_id=fid);
 r:=private.hub_kpi_publish_provisional_supplier_costs_v1(t,g);assert (r->>'added')::integer=0,'Idempotence';
 select to_jsonb(p)into strict f from private.hub_kpi_prepared_facts p where tenant_id=t and generation_id=g and fact_id=fid;
 insert into private.hub_kpi_prepared_facts select (jsonb_populate_record(null::private.hub_kpi_prepared_facts,f||jsonb_build_object(
 'fact_id','replacement-test:'||gen_random_uuid()::text,'source','NEXT','original',jsonb_build_object('Leverantör',e.supplier_name,'test_only',true)))).*;
 r:=private.hub_kpi_publish_provisional_supplier_costs_v1(t,g);
 assert not exists(select 1 from private.hub_kpi_prepared_facts where tenant_id=t and generation_id=g and fact_id=fid),'Actual cost suppresses estimate';
 assert not exists(select 1 from private.hub_kpi_prepared_display_facts where tenant_id=t and generation_id=g and fact_id=fid),'Display estimate removed too';
 r:=private.hub_kpi_publish_provisional_supplier_costs_v1(t,g);assert (r->>'added')::integer=0,'No duplicate after replacement';
 assert exists(select 1 from private.hub_kpi_provisional_supplier_costs where id=e.id),'Approval and original estimate retained';
end $$;
select 'provisional cost tests passed' result;
rollback;
