create or replace function private.hub_apply_stena_priority_v1(p_tenant uuid,p_generation uuid)returns jsonb
language plpgsql set search_path='' set jit=off as $$
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
 and s.registration<>''and(s.registration=regexp_replace(upper(up.period_data->>'name'),'[^A-Z0-9]','','g')or s.registration=regexp_replace(upper(up.period_data#>>'{main_vehicle,source_reference}'),'[^A-Z0-9]','','g'))
 )m on true
 left join lateral(
 select u.id,up.period_data as p from public.hub_objects u cross join lateral jsonb_array_elements(u.data->'periods')as up(period_data)
 where u.id=cfg.fallback_unit_id and u.tenant_id=p_tenant and u.status='active'and coalesce((up.period_data->>'enabled')::boolean,false)
 and(up.period_data->>'valid_from')::date<=s.occurred_on and((up.period_data->>'valid_to')is null or(up.period_data->>'valid_to')::date>=s.occurred_on)
 )fb on true;
 if exists(select revenue_object_id from stena_routes group by 1 having count(*)<>1)or exists(select 1 from stena_routes where target_id is null)then raise exception 'Ambiguous or missing canonical routing';end if;
 insert into private.hub_kpi_prepared_facts(generation_id,tenant_id,fiscal_year,fact_id,occurred_on,kind,amount,category,project,vehicle,unit_id,unit_name,business_group,source,description,file_name,row_number,original,cost_center,cost_center_name,classification_source,display_original)
 select p_generation,p_tenant,extract(year from s.occurred_on)::int-case when extract(month from s.occurred_on)<9 then 1 else 0 end,
 s.revenue_object_id::text,s.occurred_on,'revenue',s.amount,'transport',
 (select e->>'source_reference'from jsonb_array_elements(s.period->'members')e where e->>'kind'='project'order by(e->>'object_id'=s.period#>>'{main_vehicle,object_id}')desc nulls last limit 1),
 case when not s.fallback then s.registration end,s.target_id,s.period->>'name',coalesce(g.name,'Stena'),'Stena portal','Stena transport',s.file_name,s.row_number,
 j.meta,'30','Transport',jsonb_build_object('reason','stena_excel_priority','canonical_revenue_object_id',s.revenue_object_id),j.meta
 from stena_routes s left join public.kpi_business_groups g on g.id=(s.period->>'business_group_id')::uuid and g.tenant_id=p_tenant
 cross join lateral(select jsonb_build_object('_humla_stena_portal',jsonb_build_object('revenue_object_id',s.revenue_object_id,'file_hash',s.file_hash,'row_number',s.row_number,'booking',s.booking,'source_kind',s.source_kind,'price',s.price,'extra',s.extra,'load_count',s.load_count,'settled_amount',s.settled_amount,'fallback',s.fallback),'Kundnamn','Stena Recycling AB','RegNr',s.registration,'Summa',s.amount,'Artikeldatum',s.occurred_on,'_humla_cost_center','30','_humla_invoice',jsonb_build_object('customer_name','Stena Recycling AB','article_date',s.occurred_on,'end_date',s.occurred_on,'invoice_date',null,'order_number',s.booking))meta)j
 where s.amount<>0 and not exists(select 1 from stena_blocked b where b.id=s.revenue_object_id);
 insert into private.hub_kpi_prepared_display_facts
 select generation_id,tenant_id,fiscal_year,fact_id,occurred_on,kind,amount,category,project,vehicle,unit_id,unit_name,business_group,source,cost_center,display_original from private.hub_kpi_prepared_facts
 where tenant_id=p_tenant and generation_id=p_generation and original?'_humla_stena_portal';
 select coalesce(sum(amount),0)into added from stena_current s where s.amount is not null and not exists(select 1 from stena_blocked b where b.id=s.revenue_object_id);
 select coalesce(sum(amount),0)into after_total from private.hub_kpi_prepared_facts where tenant_id=p_tenant and generation_id=p_generation;
 if after_total<>before_total-removed+added then raise exception 'Stena financial conservation failed';end if;
 res:=jsonb_build_object('source_rows',(select count(*)from stena_current),'known_rows',(select count(*)from stena_current where amount is not null),'unpriced_rows',(select count(*)from stena_current where amount is null),'blocked_rows',(select count(*)from stena_blocked),'superseded_workify_rows',(select count(*)from stena_edges),'superseded_workify_amount',removed,'portal_amount',added,'revenue_change',added-removed,'fallback_rows',(select count(*)from stena_routes where fallback),'retained_workify_rows',(select count(*)from private.hub_kpi_prepared_facts where tenant_id=p_tenant and generation_id=p_generation and kind='revenue'and source='Workify'and original->>'Kundnamn'in('Elleholms Maskin (STENA)','Stena Recycling AB')));
 insert into private.hub_stena_projection_summary_v1 values(p_tenant,p_generation,res,now())on conflict(tenant_id,generation_id)do update set summary=excluded.summary,updated_at=now();
 update private.hub_kpi_report_state set correction_revision=correction_revision+1 where tenant_id=p_tenant;
 return res;
end $$;
revoke all on function private.hub_apply_stena_priority_v1(uuid,uuid)from public,anon,authenticated;
