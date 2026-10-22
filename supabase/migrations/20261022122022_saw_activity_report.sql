create or replace function private.hub_apply_saw_activity_v1(p_tenant uuid,p_generation uuid)
returns void language plpgsql security definer set search_path='' as $$
declare r private.hub_saw_activity_rules_v1;f private.hub_kpi_prepared_facts;outrow private.hub_kpi_prepared_facts;
 hours numeric;share numeric;allocation numeric;why text;meta jsonb;project_id uuid;before_totals jsonb;after_totals jsonb;
begin
 select * into r from private.hub_saw_activity_rules_v1 where tenant_id=p_tenant;
 if not found then return;end if;
 perform pg_advisory_xact_lock(hashtextextended('cost-allocation:'||p_tenant::text,0));
 select jsonb_agg(to_jsonb(x) order by fiscal_year,kind) into before_totals from(select fiscal_year,kind,sum(amount)amount from private.hub_kpi_prepared_facts where tenant_id=p_tenant and generation_id=p_generation group by 1,2)x;
 for f in select * from private.hub_kpi_prepared_facts where tenant_id=p_tenant and generation_id=p_generation and occurred_on>=r.valid_from and not(original?'_humla_saw_activity') and
 ((kind='revenue' and source='Workify' and original->>'Artikelnummer'='12-04') or(kind='cost' and (source like 'NEXT%' )))
 loop
  hours:=null;share:=null;why:=null;allocation:=null;
  if f.kind='revenue' then
   if f.unit_id is null or f.unit_id=r.unit_id or lower(trim(f.original->>'Enhet'))not in('tim','h','timme','timmar') or not coalesce(trim(f.original->>'Kvantitet')~'^-?[0-9]+([.,][0-9]+)?$',false)then continue;end if;
   hours:=replace(trim(f.original->>'Kvantitet'),',','.')::numeric;
   allocation:=f.amount-hours*r.truck_hour_rate;why:='article_hour_split';
  else
   -- An invoice line that also matches a project is allocated once; the explicit supplier share wins.
   if lower(trim(f.original->>'Leverantör'))=lower(r.supplier_name) and f.source='NEXT' then
    share:=r.supplier_share;why:='supplier_50_percent';
   else
    select public.hub_resolve_canonical_object_v1(p_tenant,k.object_id) into project_id from public.hub_identity_keys k
     where k.tenant_id=p_tenant and k.identity_type='next_project_number' and k.identity_value=f.project limit 1;
    if project_id=any(r.project_ids)then share:=1;why:='confirmed_saw_project';
    elsif project_id=r.review_project_id and concat_ws(' ',f.description,f.original->>'Verifikationstext',f.original->>'AO/ÄTA-benämning',f.original->>'Beskrivning')~*'(sågning|trädfäll|kransåg|beskärning)'then
     share:=1;why:='saw_evidence_on_shared_project';
    else continue;end if;
   end if;
   allocation:=case when share=1 then f.amount else round(f.amount*share,2) end;
  end if;
  meta:=jsonb_build_object('rule','saw_activity_v1','reason',why,'original_fact_id',f.fact_id,'original_amount',f.amount,'original_unit_id',f.unit_id,'original_unit_name',f.unit_name,'original_cost_center',f.cost_center,'hours',hours,'truck_hour_rate',r.truck_hour_rate,'allocated_amount',allocation,'share',share);
  -- Retain full source evidence and earlier allocation history in both branches.
  outrow:=f;outrow.fact_id:=f.fact_id||':saw';outrow.amount:=allocation;outrow.unit_id:=r.unit_id;outrow.unit_name:='Sågning';outrow.business_group:='Sågning';outrow.cost_center:='30';outrow.vehicle:=null;
  outrow.original:=f.original||jsonb_build_object('_humla_saw_activity',meta||jsonb_build_object('branch','saw'));
  if f.kind='revenue' then outrow.original:=outrow.original||jsonb_build_object('Kvantitet','0');end if;
  outrow.display_original:=coalesce(f.display_original,'{}')||jsonb_build_object('_humla_saw_activity',meta||jsonb_build_object('branch','saw'));
  insert into private.hub_kpi_prepared_facts select (outrow).*;
  update private.hub_kpi_prepared_facts set amount=f.amount-allocation,
   original=f.original||jsonb_build_object('_humla_saw_activity',meta||jsonb_build_object('branch','retained')),
   display_original=coalesce(f.display_original,'{}')||jsonb_build_object('_humla_saw_activity',meta||jsonb_build_object('branch','retained'))
   where tenant_id=p_tenant and generation_id=p_generation and fact_id=f.fact_id;
 end loop;
 delete from private.hub_kpi_prepared_display_facts d using private.hub_kpi_prepared_facts ff where ff.tenant_id=p_tenant and ff.generation_id=p_generation and ff.original?'_humla_saw_activity' and d.tenant_id=ff.tenant_id and d.generation_id=ff.generation_id and d.fact_id=ff.fact_id;
 insert into private.hub_kpi_prepared_display_facts select generation_id,tenant_id,fiscal_year,fact_id,occurred_on,kind,amount,category,project,vehicle,unit_id,unit_name,business_group,source,cost_center,display_original from private.hub_kpi_prepared_facts where tenant_id=p_tenant and generation_id=p_generation and original?'_humla_saw_activity';
 select jsonb_agg(to_jsonb(x) order by fiscal_year,kind) into after_totals from(select fiscal_year,kind,sum(amount)amount from private.hub_kpi_prepared_facts where tenant_id=p_tenant and generation_id=p_generation group by 1,2)x;
 if before_totals is distinct from after_totals then raise exception 'Saw allocation changed financial totals';end if;
end $$;
revoke all on function private.hub_apply_saw_activity_v1(uuid,uuid)from public,anon,authenticated;
create or replace function public.hub_saw_activity_report_v1(p_tenant uuid,p_from date,p_to date,p_user uuid default null,p_unit uuid default null,p_months integer[] default null)
returns jsonb language plpgsql stable security definer set search_path='' set jit='off' as $$
declare answer jsonb;complete_scope boolean;begin
 if p_months is not null and(cardinality(p_months)=0 or not p_months<@array[1,2,3,4,5,6,7,8,9,10,11,12])then raise exception 'Invalid months';end if;
 complete_scope:=p_user is null and p_unit is null and exists(select 1 from public.hub_tenant_members where tenant_id=p_tenant and user_id=auth.uid() and role='owner' and status='active');
 with authorized as materialized(select d.*,f.original evidence from private.hub_transport_leader_facts_v2(p_tenant,p_from,p_to,p_user)d
 join private.hub_kpi_prepared_facts f on f.tenant_id=d.tenant_id and f.generation_id=d.generation_id and f.fact_id=d.fact_id
 where p_months is null or extract(month from d.occurred_on)::int=any(p_months)),
 revenue as materialized(select distinct on(evidence#>>'{_humla_saw_activity,original_fact_id}')
 evidence#>>'{_humla_saw_activity,original_fact_id}' row_id,occurred_on,
 evidence#>>'{_humla_saw_activity,original_unit_id}' unit_id,evidence#>>'{_humla_saw_activity,original_unit_name}' unit_name,
 evidence->>'Ordernummer' order_number,evidence->>'Kundnamn' customer,evidence->>'Rubrik' description,
 (evidence#>>'{_humla_saw_activity,original_amount}')::numeric gross_revenue,
 (evidence#>>'{_humla_saw_activity,hours}')::numeric hours,
 (evidence#>>'{_humla_saw_activity,hours}')::numeric*(evidence#>>'{_humla_saw_activity,truck_hour_rate}')::numeric truck_revenue,
 (evidence#>>'{_humla_saw_activity,allocated_amount}')::numeric saw_revenue
 from authorized where kind='revenue' and evidence#>>'{_humla_saw_activity,reason}'='article_hour_split'
 and(p_unit is null or unit_id=p_unit or evidence#>>'{_humla_saw_activity,original_unit_id}'=p_unit::text)
 order by evidence#>>'{_humla_saw_activity,original_fact_id}',fact_id),
 costs as materialized(select fact_id,occurred_on,project,category,amount,evidence->>'Leverantör' supplier,evidence->>'Verifikation nr' voucher,evidence->>'Verifikationstext' description,
 evidence#>>'{_humla_saw_activity,reason}' allocation_reason
 from authorized where kind='cost' and evidence#>>'{_humla_saw_activity,branch}'='saw' and(p_unit is null or unit_id=p_unit)),
 pending as(select fact_id,occurred_on,project,amount,evidence->>'Leverantör' supplier,evidence->>'Verifikation nr' voucher,evidence->>'Verifikationstext' description
 from authorized f where kind='cost' and amount<>0 and not(evidence?'_humla_saw_activity') and(p_unit is null or unit_id=p_unit)
 and exists(select 1 from public.hub_identity_keys k join private.hub_saw_activity_rules_v1 r on r.tenant_id=k.tenant_id and r.review_project_id=public.hub_resolve_canonical_object_v1(k.tenant_id,k.object_id)
 where k.tenant_id=f.tenant_id and k.identity_type='next_project_number' and k.identity_value=f.project)),
 orders as(select coalesce(order_number,row_id)order_key,order_number,unit_id,min(unit_name)unit_name,min(occurred_on)first_date,max(occurred_on)last_date,min(customer)customer,min(description)description,sum(gross_revenue)gross_revenue,sum(hours)hours,sum(truck_revenue)truck_revenue,sum(saw_revenue)saw_revenue from revenue group by coalesce(order_number,row_id),order_number,unit_id),
 units as(select unit_id,min(unit_name)unit_name,count(distinct coalesce(order_number,row_id))orders,sum(gross_revenue)gross_revenue,sum(hours)hours,sum(truck_revenue)truck_revenue,sum(saw_revenue)saw_revenue from revenue group by unit_id),
 groups as(select allocation_reason,sum(amount)amount,count(*)rows from costs group by allocation_reason)
 select jsonb_build_object('complete_scope',complete_scope,'summary',(select jsonb_build_object('gross_revenue',sum(gross_revenue),'hours',sum(hours),'truck_revenue',sum(truck_revenue),'saw_revenue',sum(saw_revenue),'orders',count(distinct coalesce(order_number,row_id)),
 'cost',case when complete_scope then coalesce((select sum(amount)from costs),0)else(select sum(amount)from costs)end,
 'result',case when complete_scope then coalesce(sum(saw_revenue),0)-coalesce((select sum(amount)from costs),0)end,
 'pending_rows',(select count(*)from pending),'pending_amount',(select sum(amount)from pending))from revenue),
 'units',(select coalesce(jsonb_agg(to_jsonb(u)order by unit_name),'[]')from units u),
 'orders',(select coalesce(jsonb_agg(to_jsonb(o)order by last_date desc,order_key),'[]')from orders o),
 'costs',(select coalesce(jsonb_agg(to_jsonb(c)order by occurred_on desc,fact_id),'[]')from costs c),
 'cost_groups',(select coalesce(jsonb_agg(to_jsonb(g)order by allocation_reason),'[]')from groups g),
 'pending',(select coalesce(jsonb_agg(to_jsonb(p)order by occurred_on desc,fact_id),'[]')from pending p))into answer;
 return answer;
end $$;
revoke all on function public.hub_saw_activity_report_v1(uuid,date,date,uuid,uuid,integer[])from public,anon;
grant execute on function public.hub_saw_activity_report_v1(uuid,date,date,uuid,uuid,integer[])to authenticated;
