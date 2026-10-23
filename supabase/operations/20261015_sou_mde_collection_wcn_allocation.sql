begin;
select set_config('request.jwt.claim.sub','5a6fa4c4-5427-47fa-9835-d997fe81c7d5',true);
do $$
declare t uuid:='944597b6-9c46-4bef-998d-f19e23c4245b';target uuid;source_unit record;r public.hub_cost_allocation_rules;
begin
 perform pg_advisory_xact_lock(hashtextextended('report-collections:'||t::text,0));
 select id into strict target from public.hub_objects where tenant_id=t and object_type='EconomicUnit' and data->>'report_fallback'='unresolved';
 for source_unit in select id,data->>'name' name from public.hub_objects where tenant_id=t and object_type='EconomicUnit' and data->>'name' in('SOU57P','MDE75S')
 loop
  if not exists(select 1 from public.hub_object_relations where tenant_id=t and from_object_id=source_unit.id and to_object_id=target and relation_type='reports_in' and status='active')then
   insert into public.hub_object_relations(tenant_id,from_object_id,to_object_id,relation_type,valid_from,confidence,status,evidence)
   values(t,source_unit.id,target,'reports_in','2025-09-01 00:00:00+02',1,'active',
    jsonb_build_object('confirmed_by',auth.uid(),'confirmed_on','2026-10-15','reason','User explicitly grouped SOU57P and MDE75S under Övrigt','source_name',source_unit.name));
  end if;
 end loop;
 if (select count(*)from public.hub_object_relations where tenant_id=t and to_object_id=target and relation_type='reports_in' and status='active')<>2 then raise exception 'Unexpected report grouping members';end if;
 select * into strict r from public.hub_cost_allocation_rules where tenant_id=t and name='Bygg & Anläggning – gemensamma släp/jiggar' for update;
 if not(r.source_scope->'source_unit_names'?'WCN517')then
  update public.hub_cost_allocation_rules set source_scope=jsonb_set(source_scope,'{source_unit_names}',(source_scope->'source_unit_names')||'["WCN517"]'::jsonb),
    notes=notes||' Beslut 2026-10-15: WCN517 tillagd som gemensam kostnad för bekräftade mottagare i Bygg & Anläggning, lika andel per giltig enhet vid respektive datum (sju före 2026-09-07, åtta därefter).'
  where id=r.id;
 end if;
end $$;
create temporary table collection_before_totals on commit drop as
select date_trunc('month',occurred_on) as period_month,kind,cost_center,category,sum(amount)amount
from private.hub_kpi_prepared_facts f join private.hub_kpi_report_state s on s.tenant_id=f.tenant_id and s.active_generation=f.generation_id
where f.tenant_id='944597b6-9c46-4bef-998d-f19e23c4245b'group by 1,2,3,4;
select private.hub_apply_cost_allocation_v1(tenant_id,active_generation)allocation from private.hub_kpi_report_state where tenant_id='944597b6-9c46-4bef-998d-f19e23c4245b';
select private.hub_kpi_apply_report_collections_v1(tenant_id,active_generation)collected from private.hub_kpi_report_state where tenant_id='944597b6-9c46-4bef-998d-f19e23c4245b';
do $$begin
 if exists(
  (select * from pg_temp.collection_before_totals except
   select date_trunc('month',occurred_on),kind,cost_center,category,sum(amount)from private.hub_kpi_prepared_facts f
   join private.hub_kpi_report_state s on s.tenant_id=f.tenant_id and s.active_generation=f.generation_id
   where f.tenant_id='944597b6-9c46-4bef-998d-f19e23c4245b'group by 1,2,3,4)
  union all
  (select date_trunc('month',occurred_on),kind,cost_center,category,sum(amount)from private.hub_kpi_prepared_facts f
   join private.hub_kpi_report_state s on s.tenant_id=f.tenant_id and s.active_generation=f.generation_id
   where f.tenant_id='944597b6-9c46-4bef-998d-f19e23c4245b'group by 1,2,3,4
   except select * from pg_temp.collection_before_totals)
 )then raise exception 'Grouping/allocation changed financial totals';end if;
end $$;
update private.hub_kpi_report_state set correction_revision=coalesce(correction_revision,0)+1 where tenant_id='944597b6-9c46-4bef-998d-f19e23c4245b';
commit;
