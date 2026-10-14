-- Run with task.tenant_id and a verified KPI manager JWT subject. Always roll back.
begin;
do $$
declare t uuid:=current_setting('task.tenant_id')::uuid;g uuid;target uuid;material uuid;n integer;f jsonb;id text:='routing-test-'||gen_random_uuid()::text;
begin
 select active_generation into g from private.hub_kpi_report_state where tenant_id=t;
 select target_unit_id into target from private.hub_workify_article_unit_rules where tenant_id=t and article_contains='hjullastare' and enabled;
 select material_unit_id into material from private.hub_kpi_material_separation_settings where tenant_id=t;
 assert target is not null and material is not null;
 n:=private.hub_apply_workify_article_units_v1(t,g);assert n=0,'Rerun must be idempotent';
 select to_jsonb(p) into f from private.hub_kpi_prepared_facts p where tenant_id=t and generation_id=g and source='Workify' and kind='revenue' and occurred_on='2026-09-01' limit 1;
 assert f is not null;
 insert into private.hub_kpi_prepared_facts select (jsonb_populate_record(null::private.hub_kpi_prepared_facts,f||jsonb_build_object('fact_id',id,'unit_id',null,'vehicle',null,'project',null,'original',jsonb_build_object('Artikelnamn','Hyra HJULLASTARE med tillbehör'),'description','TEST','display_original','{}'::jsonb))).*;
 insert into private.hub_kpi_prepared_facts select (jsonb_populate_record(null::private.hub_kpi_prepared_facts,f||jsonb_build_object('fact_id',id||'-cost','kind','cost','unit_id',null,'original',jsonb_build_object('Artikelnamn','HJULLASTARE'),'display_original','{}'::jsonb))).*;
 n:=private.hub_apply_workify_article_units_v1(t,g);assert n=1,'Contains match must route new revenue only';
 assert exists(select 1 from private.hub_kpi_prepared_facts where generation_id=g and fact_id=id and unit_id=target and vehicle='ZLA906');
 assert exists(select 1 from private.hub_kpi_prepared_facts where generation_id=g and fact_id=id||'-cost' and unit_id is null);
 assert private.hub_apply_workify_article_units_v1(t,g)=0,'Second application must be idempotent';
 begin
  insert into private.hub_workify_article_unit_rules(tenant_id,article_contains,target_unit_id,valid_from,approval_reference,created_by) values(t,'HJULLASTARE',material,'2025-09-01','test conflict',auth.uid());
  perform private.hub_apply_workify_article_units_v1(t,g);
  raise exception 'Missing conflict detection' using errcode='XX000';
 exception when raise_exception then
  assert sqlerrm='Conflicting article routing requires review';
 end;
end $$;
select 'article routing tests passed' result;
rollback;
