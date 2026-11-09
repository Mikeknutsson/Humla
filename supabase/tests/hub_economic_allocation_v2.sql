-- Run inside BEGIN/ROLLBACK with request.jwt.claim.sub and test.tenant_id.
do $test$
declare tenant uuid:=current_setting('test.tenant_id')::uuid;actor uuid:=auth.uid();
 batches uuid[]:=array[gen_random_uuid(),gen_random_uuid()];prefix text:='__hub_v2_test_'||gen_random_uuid();
 a jsonb;b jsonb;result jsonb;vehicles uuid[];rule jsonb;saved jsonb;retry jsonb;total numeric;
begin
 insert into public.kpi_import_batches(id,tenant_id,source_type,data_kind,file_name,file_hash,created_by,row_count)
 select id,tenant,'manual_excel','cost','__hub_v2_rollback.xlsx',md5(id::text)||md5(id::text),actor,3 from unnest(batches)id;
 a:=jsonb_build_object('row_number',1,'data_kind','cost','occurred_on','2026-09-03','amount',100,'currency','SEK','project_reference',prefix,
 'is_valid',false,'validation_errors','["Kostnadsfördelning behöver granskas"]'::jsonb,
 'source_data',jsonb_build_object('Konto','5656','Projektnr',prefix,'Verifikation nr',prefix,'Nettobelopp','100','Fakturerat','FALSE'));
 result:=public.hub_kpi_ingest_cost_file_v1(tenant,batches[1],jsonb_build_array(a,jsonb_set(a,'{row_number}','2')));
 if (result->>'insertedRows')::int<>2 or (result->>'validRows')::int<>2 then raise exception 'Unallocated financial rows lost: %',result;end if;
 b:=jsonb_set(jsonb_set(a,'{row_number}','3'),'{amount}','-25');
 b:=jsonb_set(b,'{source_data,Verifikation nr}',to_jsonb(prefix||'CREDIT'));
 result:=public.hub_kpi_ingest_cost_file_v1(tenant,batches[2],jsonb_build_array(jsonb_set(a,'{source_data,Fakturerat}','"TRUE"'),jsonb_set(a,'{row_number}','2'),b));
 if (result->>'insertedRows')::int<>1 or (result->>'duplicateRowsSkipped')::int<>2 then raise exception 'Overlap/status/multiplicity failed: %',result;end if;
 if public.hub_kpi_ingest_cost_file_v1(tenant,batches[2],jsonb_build_array(a))<>result then raise exception 'Retry not idempotent';end if;
 select sum(amount)into total from private.hub_economic_transactions_compact_v2(tenant,'2026-09-01','2026-09-30')
 where project=prefix and economic_status='included';
 if total<>175 then raise exception 'Source total did not retain credit and legitimate multiplicity: %',total;end if;
 select array_agg(id)into vehicles from(select distinct o.id from public.hub_objects o join public.hub_identity_keys k on k.object_id=o.id and k.tenant_id=o.tenant_id
 where o.tenant_id=tenant and lower(o.object_type)='vehicle' and k.identity_type='registration_number' and k.confidence=1 order by o.id limit 2)v;
 if cardinality(vehicles)<2 then raise exception 'Two canonical fixture vehicles required';end if;
 rule:=jsonb_build_object('dimension','vehicle','evidenceType','project','evidenceValue',prefix,'targetObjectId',vehicles[1],
 'sourceFamily','NEXT','kind','cost','from','2026-09-01','to','2026-09-30','reason','Rollback-only confirmed mapping test');
 saved:=public.hub_allocation_rule_confirm_v2(tenant,rule);retry:=public.hub_allocation_rule_confirm_v2(tenant,rule);
 if saved->>'id'<>retry->>'id' then raise exception 'Confirmation retry duplicates knowledge';end if;
 begin
 perform public.hub_allocation_rule_confirm_v2(tenant,jsonb_set(rule,'{targetObjectId}',to_jsonb(vehicles[2])));
 raise exception 'Conflicting overlapping rule accepted';exception when unique_violation then null;end;
 begin
 perform public.hub_allocation_rule_confirm_v2(gen_random_uuid(),rule);
 raise exception 'Foreign tenant accepted';exception when insufficient_privilege then null;end;
 if exists(select 1 from private.hub_economic_transactions_compact_v2(tenant,'2026-09-01','2026-09-30')
 where project=prefix and economic_status='included' and (vehicle_object_id is distinct from vehicles[1] or allocation_status<>'verified')) then raise exception 'Confirmed knowledge not applied historically';end if;
 if (select sum(amount)from private.hub_economic_transactions_compact_v2(tenant,'2026-09-01','2026-09-30')where project=prefix and economic_status='included')<>175 then raise exception 'Mapping changed total';end if;
 if (select count(*)from public.hub_allocation_mapping_events where rule_id=(saved->>'id')::uuid)<>1 then raise exception 'Audit missing or duplicated';end if;
 if has_table_privilege('authenticated','public.hub_allocation_mapping_rules','insert') then raise exception 'Direct write bypass';end if;
 if has_function_privilege('anon','public.hub_kpi_economic_reconciliation_v3(uuid,date,date,jsonb,integer)','execute') then raise exception 'Anonymous report access';end if;
end $test$;
select 'PASS overlap, multiplicity, credits, unallocated inclusion, retry, permanent dated mapping, conflict, tenant isolation, audit and permissions' as test;
