CREATE OR REPLACE FUNCTION private.hub_apply_stena_priority_v1(p_tenant uuid, p_generation uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
 SET jit TO 'off'
AS $function$
declare cfg private.hub_stena_rules_v1; n int; before_total numeric; after_total numeric;removed numeric;added numeric;res jsonb;
begin
 if auth.uid()is null or not public.hub_has_permission(p_tenant,'kpi.manage')then raise exception 'Access denied'using errcode='42501';end if;
 select * into cfg from private.hub_stena_rules_v1 where tenant_id=p_tenant and enabled;
 if not found then return jsonb_build_object('enabled',false);end if;
 if not exists(select 1 from private.hub_kpi_report_generations where id=p_generation and tenant_id=p_tenant)then raise exception 'Generation mismatch';end if;
 perform pg_advisory_xact_lock(hashtextextended('stena-projection:'||p_tenant::text,0));
 -- Restore the original derived Workify projection before recomputing; raw imports are untouched.
 delete from private.hub_kpi_prepared_display_facts where tenant_id=p_tenant and generation_id=p_generation and original?'_humla_stena_portal';
 delete from private.hub_kpi_prepared_facts where tenant_id=p_tenant and generation_id=p_generation and original?'_humla_stena_portal';
 insert into private.hub_kpi_prepared_facts
 select (jsonb_populate_record(null::private.hub_kpi_prepared_facts,a.before_fact)).* from private.hub_stena_projection_audit_v1 a
 where a.tenant_id=p_tenant and a.generation_id=p_generation and not exists(select 1 from private.hub_kpi_prepared_facts f where f.generation_id=p_generation and f.tenant_id=p_tenant and f.fact_id=a.fact_id);
 insert into private.hub_kpi_prepared_display_facts
 select(jsonb_populate_record(null::private.hub_kpi_prepared_display_facts,a.before_display)).* from private.hub_stena_projection_audit_v1 a
 where a.tenant_id=p_tenant and a.generation_id=p_generation and a.before_display is not null and not exists(select 1 from private.hub_kpi_prepared_display_facts f where f.generation_id=p_generation and f.tenant_id=p_tenant and f.fact_id=a.fact_id);
 select coalesce(sum(amount),0)into before_total from private.hub_kpi_prepared_facts where tenant_id=p_tenant and generation_id=p_generation;
 create temporary table stena_current on commit drop as
 select distinct on(r.revenue_object_id)r.*,f.file_name,f.source_kind from private.hub_stena_rows_v1 r join private.hub_stena_files_v1 f using(tenant_id,file_hash)
 where r.tenant_id=p_tenant and f.complete order by r.revenue_object_id,(f.source_kind='settled')desc,f.uploaded_at desc,f.file_hash;
 update stena_current s set amount=o.amount from private.hub_stena_amount_overrides_v1 o where o.tenant_id=p_tenant and o.revenue_object_id=s.revenue_object_id;
create unique index on stena_current(revenue_object_id);
 create unique index on stena_current(booking);
 create temporary table stena_edges on commit drop as
 select f.fact_id,array_agg(distinct s.revenue_object_id)portal_ids
 from private.hub_kpi_prepared_facts f
 cross join lateral regexp_matches(coalesce(f.original->>'Littranummer','')||' '||coalesce(f.original->>'ArtikelKommentar',''),'(?<![0-9])[0-9]{8}(?![0-9])','g')k
 join stena_current s on s.booking=k[1]
 where f.tenant_id=p_tenant and f.generation_id=p_generation and f.kind='revenue'and f.source='Workify'
 and f.original->>'Kundnamn'in('Elleholms Maskin (STENA)','Stena Recycling AB')
 and not coalesce((f.original->>'_humla_excluded_from_kpi')::boolean,false)
 group by f.fact_id;
 create temporary table stena_blocked(id uuid primary key)on commit drop;
 insert into stena_blocked select revenue_object_id from stena_current where amount is null;
 loop
 insert into stena_blocked select distinct unnest(e.portal_ids)from stena_edges e where exists(select 1 from stena_blocked b where b.id=any(e.portal_ids))on conflict do nothing;
 get diagnostics n=row_count;exit when n=0;
 end loop;
 delete from stena_edges e where exists(select 1 from stena_blocked b where b.id=any(e.portal_ids));
 insert into private.hub_stena_projection_audit_v1(tenant_id,generation_id,fact_id,before_fact,before_display,portal_ids)
 select p_tenant,p_generation,f.fact_id,to_jsonb(f),to_jsonb(d),e.portal_ids from stena_edges e
 join private.hub_kpi_prepared_facts f on f.fact_id=e.fact_id and f.generation_id=p_generation and f.tenant_id=p_tenant
 left join private.hub_kpi_prepared_display_facts d on d.fact_id=f.fact_id and d.generation_id=f.generation_id and d.tenant_id=f.tenant_id
 on conflict(tenant_id,generation_id,fact_id)do update set portal_ids=excluded.portal_ids;
 select coalesce(sum(f.amount),0)into removed from private.hub_kpi_prepared_facts f join stena_edges e using(fact_id)where f.tenant_id=p_tenant and f.generation_id=p_generation;
 delete from private.hub_kpi_prepared_display_facts f using stena_edges e where f.tenant_id=p_tenant and f.generation_id=p_generation and f.fact_id=e.fact_id;
 delete from private.hub_kpi_prepared_facts f using stena_edges e where f.tenant_id=p_tenant and f.generation_id=p_generation and f.fact_id=e.fact_id;
 create temporary table stena_routes on commit drop as
 select s.*,coalesce(m.id,fb.id)target_id,coalesce(m.p,fb.p)period,m.id is null fallback
 from stena_current s
 left join lateral(
 select u.id,up.period_data as p from public.hub_objects u cross join lateral jsonb_array_elements(u.data->'periods')as up(period_data)
 where u.tenant_id=p_tenant and u.object_type='EconomicUnit'and u.status='active'
 and up.period_data->>'unit_type'in('vehicle','compound')and coalesce((up.period_data->>'enabled')::boolean,false)
 and(up.period_data->>'valid_from')::date<=s.occurred_on and((up.period_data->>'valid_to')is null or(up.period_data->>'valid_to')::date>=s.occurred_on)
 and s.registration<>''and(s.registration=regexp_replace(upper(up.period_data->>'name'),'[^A-Z0-9]','','g')or s.registration=regexp_replace(upper(up.period_data#>>'{main_vehicle,source_reference}'),'[^A-Z0-9]','','g')or exists(select 1 from public.hub_identity_keys ik where ik.tenant_id=p_tenant and ik.identity_type='stena_vehicle_registration'and ik.identity_value=s.registration and ik.object_id::text=up.period_data#>>'{main_vehicle,object_id}'))
 )m on true
 left join lateral(
 select u.id,up.period_data as p from public.hub_objects u cross join lateral jsonb_array_elements(u.data->'periods')as up(period_data)
 where u.id=cfg.fallback_unit_id and u.tenant_id=p_tenant and u.status='active'and coalesce((up.period_data->>'enabled')::boolean,false)
 and(up.period_data->>'valid_from')::date<=s.occurred_on and((up.period_data->>'valid_to')is null or(up.period_data->>'valid_to')::date>=s.occurred_on)
 )fb on true;
 -- Missing historical mappings remain financially included and explicitly unallocated.
 if exists(select revenue_object_id from stena_routes group by 1 having count(*)<>1)then raise exception 'Ambiguous canonical routing';end if;
 insert into private.hub_kpi_prepared_facts(generation_id,tenant_id,fiscal_year,fact_id,occurred_on,kind,amount,category,project,vehicle,unit_id,unit_name,business_group,source,description,file_name,row_number,original,cost_center,cost_center_name,classification_source,display_original)
 select p_generation,p_tenant,extract(year from s.occurred_on)::int-case when extract(month from s.occurred_on)<9 then 1 else 0 end,
 s.revenue_object_id::text,s.occurred_on,'revenue',s.amount,'transport',
 (select e->>'source_reference'from jsonb_array_elements(s.period->'members')e where e->>'kind'='project'order by(e->>'object_id'=s.period#>>'{main_vehicle,object_id}')desc nulls last limit 1),
 case when not s.fallback then coalesce(s.period#>>'{main_vehicle,source_reference}',s.registration)end,s.target_id,coalesce(s.period->>'name','Stena – fördelning saknas'),coalesce(g.name,'Stena'),'Stena portal','Stena transport',s.file_name,s.row_number,
 j.meta,'30','Transport',jsonb_build_object('reason',case when s.target_id is null then 'stena_unallocated_historical' else 'stena_excel_priority' end,'allocation_status',case when s.target_id is null then 'unallocated' else 'allocated' end,'canonical_revenue_object_id',s.revenue_object_id),j.meta
 from stena_routes s left join public.kpi_business_groups g on g.id=(s.period->>'business_group_id')::uuid and g.tenant_id=p_tenant
 cross join lateral(select jsonb_build_object('_humla_stena_portal',jsonb_build_object('revenue_object_id',s.revenue_object_id,'file_hash',s.file_hash,'row_number',s.row_number,'booking',s.booking,'source_kind',s.source_kind,'confirmed_override',(select jsonb_build_object('amount',o.amount,'reason',o.reason,'approved_at',o.approved_at)from private.hub_stena_amount_overrides_v1 o where o.tenant_id=p_tenant and o.revenue_object_id=s.revenue_object_id),'price',s.price,'extra',s.extra,'load_count',s.load_count,'load_carrier_type',s.load_carrier_type,'price_basis',case when s.source_kind='settled'then 'settled_line_total'else private.hub_stena_price_basis_v1(s.load_carrier_type,s.load_count)end,'previous_amount',s.previous_amount,'settled_amount',s.settled_amount,'fallback',s.fallback),'Kundnamn','Stena Recycling AB','RegNr',s.registration,'Summa',s.amount,'Artikeldatum',s.occurred_on,'_humla_cost_center','30','_humla_invoice',jsonb_build_object('customer_name','Stena Recycling AB','article_date',s.occurred_on,'end_date',s.occurred_on,'invoice_date',null,'order_number',s.booking))meta)j
 where s.amount<>0 and not exists(select 1 from stena_blocked b where b.id=s.revenue_object_id);
 insert into private.hub_kpi_prepared_display_facts
 select generation_id,tenant_id,fiscal_year,fact_id,occurred_on,kind,amount,category,project,vehicle,unit_id,unit_name,business_group,source,cost_center,display_original from private.hub_kpi_prepared_facts
 where tenant_id=p_tenant and generation_id=p_generation and original?'_humla_stena_portal';
 select coalesce(sum(amount),0)into added from stena_current s where s.amount is not null and not exists(select 1 from stena_blocked b where b.id=s.revenue_object_id);
 select coalesce(sum(amount),0)into after_total from private.hub_kpi_prepared_facts where tenant_id=p_tenant and generation_id=p_generation;
 if after_total<>before_total-removed+added then raise exception 'Stena financial conservation failed';end if;
 res:=jsonb_build_object('source_rows',(select count(*)from stena_current),'known_rows',(select count(*)from stena_current where amount is not null),'unpriced_rows',(select count(*)from stena_current where amount is null),'blocked_rows',(select count(*)from stena_blocked),'superseded_workify_rows',(select count(*)from stena_edges),'superseded_workify_amount',removed,'portal_amount',added,'revenue_change',added-removed,'unallocated_rows',(select count(*)from stena_routes where target_id is null),'fallback_rows',(select count(*)from stena_routes where fallback and target_id is not null),'retained_workify_rows',(select count(*)from private.hub_kpi_prepared_facts where tenant_id=p_tenant and generation_id=p_generation and kind='revenue'and source='Workify'and original->>'Kundnamn'in('Elleholms Maskin (STENA)','Stena Recycling AB')));
 insert into private.hub_stena_projection_summary_v1 values(p_tenant,p_generation,res,now())on conflict(tenant_id,generation_id)do update set summary=excluded.summary,updated_at=now();
 update private.hub_kpi_report_state set correction_revision=correction_revision+1 where tenant_id=p_tenant;
 return res;
end $function$;

CREATE OR REPLACE FUNCTION public.hub_kpi_ingest_cost_file_v1(p_tenant_id uuid, p_batch_id uuid, p_rows jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET statement_timeout TO '60s'
 SET jit TO 'off'
 SET work_mem TO '64MB'
AS $function$
declare result jsonb;accepted jsonb;changed integer;received integer;conflicts jsonb;
begin
 if auth.uid()is null or not public.hub_has_permission(p_tenant_id,'kpi.manage')then raise exception 'KPI-administratör krävs'using errcode='42501';end if;
 if p_rows is null or jsonb_typeof(p_rows)<>'array'or jsonb_array_length(p_rows)>50000 then raise exception 'Ogiltig kostnadsleverans';end if;
 if exists(select 1 from jsonb_array_elements(p_rows) r where r->'source_data' ? 'Trp.best.nr' and r->'source_data' ? 'Hämtdatum' and r->'source_data' ? 'Pris SEK') then
  raise exception 'Stena-avräkning är kundintäkt. Använd Stena-importen, inte NeXT-kostnader.' using errcode='22023';
 end if;
 perform pg_advisory_xact_lock(hashtextextended('cost-file-import:'||p_tenant_id::text,0));
 select provenance->'hub_cost_ingest_result'into result from public.kpi_import_batches where id=p_batch_id and tenant_id=p_tenant_id and data_kind='cost'for update;
 if not found then raise exception 'Kostnadsimporten saknas';end if;
 if result is not null then return result;end if;
 if exists(select 1 from jsonb_populate_recordset(null::public.kpi_import_rows,p_rows)r where r.data_kind is distinct from'cost'
 or r.row_number is null
 or(r.vehicle_object_id is not null and not exists(select 1 from public.hub_objects o where o.tenant_id=p_tenant_id and o.id=r.vehicle_object_id))
 or(r.employee_object_id is not null and not exists(select 1 from public.hub_objects o where o.tenant_id=p_tenant_id and o.id=r.employee_object_id)))then raise exception 'Invalid cost source scope';end if;
 if jsonb_array_length(p_rows)<>(select count(distinct x->>'row_number')from jsonb_array_elements(p_rows)x)then raise exception 'Duplicate physical row numbers';end if;
 received:=jsonb_array_length(p_rows);
 with incoming as materialized(
 select j.value,row_number()over()ordinal,(j.value->>'row_number')::int row_number,
 private.hub_cost_document_key_v2((j.value->>'occurred_on')::date,j.value->'source_data')doc,
 private.hub_economic_key_v2('cost',(j.value->>'occurred_on')::date,(j.value->>'amount')::numeric,(j.value->>'quantity')::numeric,j.value->>'currency',j.value->'source_data',md5((j.value->'source_data')::text))fp
 from jsonb_array_elements(p_rows)j
 ), docs as(select distinct doc from incoming),previous as materialized(
 select r.batch_id,r.source_fingerprint,
 private.hub_cost_document_key_v2(r.occurred_on,r.source_data)doc,
 private.hub_economic_key_v2('cost',r.occurred_on,r.amount,r.quantity,r.currency,r.source_data,md5(r.source_data::text))fp
 from public.kpi_import_rows r where r.tenant_id=p_tenant_id and r.data_kind='cost'
 and not(coalesce(r.validation_errors,'[]')?'Importen återtagen eller ersatt; ingår inte i beräkningar')
 and exists(select 1 from docs d where d.doc=private.hub_cost_document_key_v2(r.occurred_on,r.source_data))
 ), capacities as(
 select doc,fp,batch_id,count(*)copies,max(case when source_fingerprint~'^next-file-v1:[a-f0-9]+:[0-9]+$'then split_part(source_fingerprint,':',3)::bigint else 0 end)ordinal
 from previous group by 1,2,3
 ), known as(select doc,fp,greatest(max(copies),max(ordinal))copies from capacities group by 1,2),
 counts as(select doc,fp,count(*)copies from incoming group by 1,2),
 missing as(select distinct k.doc from known k left join counts c using(doc,fp)where coalesce(c.copies,0)<k.copies),
 unsafe as(select distinct c.doc from counts c left join known k using(doc,fp)where c.copies>coalesce(k.copies,0)and c.doc in(select doc from missing)),
 saved as(
 insert into private.hub_cost_import_observations_v2(tenant_id,batch_id,row_number,document_key,content_key,decision,source_row)
 select p_tenant_id,p_batch_id,i.row_number,i.doc,i.fp,case when u.doc is null then 'observed'else 'revision_review'end,i.value
 from incoming i left join unsafe u using(doc)
 returning row_number,decision,document_key
 )
 select coalesce(jsonb_agg(i.value order by i.ordinal)filter(where s.decision='observed'),'[]'),
 count(*)filter(where s.decision='revision_review'),
 coalesce(jsonb_agg(jsonb_build_object('row',i.row_number,'document_key',s.document_key,'reason','Befintligt bokföringsinnehåll saknas samtidigt som nytt tillkommer. Tidigare belopp behålls; andra verifikationer importeras.'))filter(where s.decision='revision_review'),'[]')
 into accepted,changed,conflicts from incoming i join saved s using(row_number);
 result:=private.hub_kpi_ingest_cost_file_base_v1(p_tenant_id,p_batch_id,accepted);
 result:=result||jsonb_build_object('receivedRows',received,'changedRows',changed,'changes',conflicts,'independentRowsAccepted',true,'revisionPolicy','retain_previous_until_source_revision_resolved',
 'status',case when changed>0 then 'needs_review'else result->>'status'end);
 update public.kpi_import_batches set status=result->>'status',error_summary=coalesce(error_summary,'[]')||conflicts,
 provenance=provenance||jsonb_build_object('hub_cost_ingest_result',result)where tenant_id=p_tenant_id and id=p_batch_id;
 return result;
end$function$;
