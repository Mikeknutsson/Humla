begin;
select set_config('request.jwt.claim.sub','5a6fa4c4-5427-47fa-9835-d997fe81c7d5',true);
do $$
declare t uuid:='944597b6-9c46-4bef-998d-f19e23c4245b';r jsonb;b jsonb;g uuid;copy_batch uuid:=gen_random_uuid();sample jsonb;hours numeric;before_money numeric;after_money numeric;
begin
 select active_generation into g from private.hub_kpi_report_state where tenant_id=t;
 select sum(amount)into before_money from private.hub_kpi_prepared_facts where tenant_id=t and generation_id=g;
 b:=private.hub_kpi_next_time_period_v1(t,2026,array[9],'{"cost_center":"20"}');
 if(b->>'project_hours')::numeric<>250 or(b->>'workshop_hours')::numeric<>42 or(b->>'supplement_hours')::numeric<>16 then raise exception 'NEXT project/repair/OB distinction failed: %',b;end if;
 r:=private.hub_kpi_next_time_period_v1(t,2026,array[9],'{"cost_center":"30"}');
 if(r->>'workshop_hours')::numeric<>25 or(r->>'workshop_hours_without_cost_reference')::numeric<>3 then raise exception 'Repair cost evidence failed: %',r;end if;
 r:=private.hub_kpi_next_time_period_v1(t,2025,array[9],'{"cost_center":"20"}');
 if(r->>'available')::boolean or r->>'project_hours' is not null then raise exception 'Missing historical import fabricated zero';end if;
 r:=private.hub_kpi_next_time_period_v1(t,2026,array[9],'{"cost_center":"20","project":"1907"}');
 if(r->>'project_hours')::numeric<>1 or(r->>'workshop_hours')::numeric<>21 then raise exception 'Project scope failed';end if;
 r:=private.hub_kpi_next_time_period_v1(t,2026,array[9],'{"cost_center":"20","unit":"5c6cf20d-327e-4525-82db-42046f78fef8"}');
 if(r->>'workshop_hours')::numeric<>21 then raise exception 'Canonical unit scope failed';end if;
 -- Clone one source export entry, then add a second identical physical entry.
 -- A repeated export must not add hours; a second entry in that export must survive.
 select to_jsonb(src),src.paid_hours into sample,hours from private.hub_kpi_prepared_kpi_import_rows src
 where src.generation_id=g and src.tenant_id=t and src.data_kind='next_historical_time'and src.description='MA'and src.paid_hours>0 limit 1;
 insert into public.kpi_import_batches select (jsonb_populate_record(null::public.kpi_import_batches,to_jsonb(x)||jsonb_build_object('id',copy_batch,'file_hash',md5(copy_batch::text)||md5(copy_batch::text)))).*
 from public.kpi_import_batches x where x.tenant_id=t and x.id=(sample->>'batch_id')::uuid;
 insert into private.hub_kpi_prepared_kpi_import_rows select (jsonb_populate_record(null::private.hub_kpi_prepared_kpi_import_rows,sample||jsonb_build_object('id',gen_random_uuid(),'batch_id',copy_batch))).*;
 r:=private.hub_kpi_next_time_period_v1(t,2026,array[9],'{"cost_center":"20"}');
 if r->>'project_hours'<>b->>'project_hours' then raise exception 'Repeated export counted twice';end if;
 insert into private.hub_kpi_prepared_kpi_import_rows select (jsonb_populate_record(null::private.hub_kpi_prepared_kpi_import_rows,sample||jsonb_build_object('id',gen_random_uuid(),'batch_id',copy_batch,'row_number',9999))).*;
 r:=private.hub_kpi_next_time_period_v1(t,2026,array[9],'{"cost_center":"20"}');
 if(r->>'project_hours')::numeric<>(b->>'project_hours')::numeric+hours then raise exception 'Legitimate repeated physical entry removed';end if;
 select sum(amount)into after_money from private.hub_kpi_prepared_facts where tenant_id=t and generation_id=g;
 if before_money<>after_money then raise exception 'Time reporting changed financial facts';end if;
 if has_function_privilege('anon','private.hub_kpi_next_time_period_v1(uuid,integer,integer[],jsonb)','execute')or has_function_privilege('authenticated','private.hub_kpi_next_time_period_v1(uuid,integer,integer[],jsonb)','execute')then raise exception 'Private helper exposed';end if;
end $$;
rollback;
