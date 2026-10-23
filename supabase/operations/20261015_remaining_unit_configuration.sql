begin;
select set_config('request.jwt.claim.sub','5a6fa4c4-5427-47fa-9835-d997fe81c7d5',true);
do $$
declare t uuid:='944597b6-9c46-4bef-998d-f19e23c4245b'; old public.kpi_unit_periods; fallback uuid;
begin
 perform pg_advisory_xact_lock(hashtextextended('remaining-unit-resolution:'||t,0));
 select * into strict old from public.kpi_unit_periods where tenant_id=t and id='aba83722-56b4-4542-8600-d5695fb8d91f' for update;
 if old.valid_to is null then
  update public.kpi_unit_periods set valid_to='2026-09-30',payload=payload||jsonb_build_object('valid_to','2026-09-30') where id=old.id;
  insert into public.kpi_unit_periods(tenant_id,unit_id,valid_from,valid_to,payload,created_by)
  values(t,old.unit_id,'2026-10-01',null,old.payload||jsonb_build_object('valid_from','2026-10-01','valid_to',null,
    'projects',coalesce((select jsonb_agg(v)from jsonb_array_elements_text(old.payload->'projects')v where v<>'9061'),'[]'),
    'registrations',coalesce((select jsonb_agg(v)from jsonb_array_elements_text(old.payload->'registrations')v where v<>'JAK62T'),'[]'),
    'source',jsonb_build_object('type','user_confirmed_latest_mapping','confirmed_on','2026-10-15','reason','JAK62T follows latest SPN03J mapping from 2026-10-01')),auth.uid());
  update public.kpi_units set projects=array_remove(projects,'9061'),registrations=array_remove(registrations,'JAK62T'),revision=revision+1 where tenant_id=t and id=old.unit_id;
 end if;
 select id into fallback from public.hub_objects where tenant_id=t and object_type='EconomicUnit' and data->>'report_fallback'='unresolved';
 if fallback is null then
  insert into public.hub_objects(tenant_id,object_type,status,data,source_of_truth,version)
  values(t,'EconomicUnit','active',jsonb_build_object('name','Övrigt','unit_type','collection','enabled',true,'report_fallback','unresolved','periods','[]'::jsonb,'components','[]'::jsonb,
    'approval',jsonb_build_object('actor',auth.uid(),'date','2026-10-15','reason','Collect only after checking confirmed dated mappings; preserve original references and cost center')),'Humla',1)returning id into fallback;
  insert into public.hub_identity_keys(tenant_id,object_id,object_type,identity_type,identity_value,confidence)values(t,fallback,'EconomicUnit','humla_report_collection','unresolved_economic_unit',1);
 end if;
end $$;
select private.hub_resolve_remaining_units_v1(tenant_id,active_generation) result from private.hub_kpi_report_state where tenant_id='944597b6-9c46-4bef-998d-f19e23c4245b';
update private.hub_kpi_report_state set correction_revision=coalesce(correction_revision,0)+1 where tenant_id='944597b6-9c46-4bef-998d-f19e23c4245b';
commit;
