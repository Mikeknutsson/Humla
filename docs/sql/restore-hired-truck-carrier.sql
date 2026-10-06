-- User-confirmed shared vehicle carrier: NEXT 9009 + Workify LASTBIL.
-- Run as the authorized KPI administrator, inside a transaction.
do $repair$
declare tenant uuid; carrier uuid; uid uuid; gid uuid; previous jsonb; payload jsonb;
begin
 select tenant_id into strict tenant from public.hub_tenant_members where user_id=auth.uid() and status='active';
 if not public.hub_has_permission(tenant,'kpi.manage') then raise exception 'KPI-administratör krävs';end if;
 select k.object_id into strict carrier from public.hub_identity_keys k
 where k.tenant_id=tenant and k.object_type='Vehicle' and k.identity_type='workify_vehicle_label' and k.identity_value='LASTBIL' and k.confidence=1;
 select id,to_jsonb(u) into strict uid,previous from public.kpi_units u
 where tenant_id=tenant and projects=array['9009'] and origin='next_project_import';
 if exists(select 1 from public.kpi_unit_periods where tenant_id=tenant and unit_id=uid) then raise exception 'Existing dated configuration requires review';end if;
 select id into strict gid from public.kpi_business_groups where tenant_id=tenant and name='Inhyrda lastbilar' and enabled;
 payload:=jsonb_build_object('name','Inhyrda bilar','unit_type','vehicle','projects',jsonb_build_array('9009'),'registrations','[]'::jsonb,'employees','[]'::jsonb,'enabled',true,'origin','manual','valid_from','2025-09-01','valid_to',null,'business_group_id',gid,'carrier_object_id',carrier);
 insert into public.kpi_unit_initial_setup_events(tenant_id,unit_id,actor,action,previous_periods,next_payload)
 values(tenant,uid,auth.uid(),'create_initial',jsonb_build_array(previous),payload);
 update public.kpi_units set name='Inhyrda bilar',unit_type='vehicle',enabled=true,origin='manual',valid_from='2025-09-01' where tenant_id=tenant and id=uid;
 insert into public.kpi_unit_periods(tenant_id,unit_id,valid_from,payload,created_by) values(tenant,uid,'2025-09-01',payload,auth.uid());
 insert into public.kpi_unit_initial_setup(unit_id,tenant_id) values(uid,tenant);
 -- Compatibility adapter references both aliases of the same canonical Vehicle.
 insert into public.kpi_unit_components(tenant_id,unit_id,component_type,component_reference,allocation_percent,valid_from)
 select tenant,uid,'vehicle',k.identity_value,100,'2025-09-01'::date from public.hub_identity_keys k
 where k.tenant_id=tenant and k.object_id=carrier and k.identity_type in ('registration_number','workify_vehicle_label') and k.confidence=1;
 -- Release only the confirmed carrier's vehicle-target article rows.
 update public.kpi_import_rows r set vehicle_object_id=carrier,vehicle_registration='LASTBIL',
 validation_errors=(select coalesce(jsonb_agg(e),'[]'::jsonb) from jsonb_array_elements_text(r.validation_errors)e where e not in ('Fordonsbeteckning saknar verifierad regnummerkoppling','Workify-artikeln ska till fordon: registreringsnummer behöver mappas')),
 is_valid=r.occurred_on is not null and r.amount is not null and r.validation_errors<@'["Fordonsbeteckning saknar verifierad regnummerkoppling","Workify-artikeln ska till fordon: registreringsnummer behöver mappas"]'::jsonb
 where r.tenant_id=tenant and r.data_kind='revenue' and upper(trim(r.source_data->>'RegNr'))='LASTBIL'
 and exists(select 1 from public.kpi_workify_article_rules a where a.tenant_id=tenant and a.enabled and a.target_type='vehicle' and a.article_number=r.source_data->>'Artikelnummer' and r.occurred_on between a.valid_from and coalesce(a.valid_to,'infinity'::date));
 update public.kpi_import_batches b set valid_row_count=x.valid,invalid_row_count=x.invalid,status=case when x.invalid=0 then 'completed' else 'needs_review' end
 from (select batch_id,count(*)filter(where is_valid)valid,count(*)filter(where not is_valid)invalid from public.kpi_import_rows where tenant_id=tenant group by batch_id)x
 where b.tenant_id=tenant and b.id=x.batch_id and b.data_kind='revenue' and b.status in ('completed','needs_review');
end $repair$;
