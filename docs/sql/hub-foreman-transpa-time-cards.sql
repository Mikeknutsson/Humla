create or replace function private.hub_foreman_time_cards_v1(p_tenant uuid,p_report jsonb,p_user uuid,p_months integer[],p_group text)
returns jsonb language plpgsql stable set search_path='' set jit='off' as $f$
declare g uuid:=(p_report->>'generation')::uuid;df date:=(p_report->>'from')::date;dt date:=(p_report->>'to')::date;answer jsonb;
begin
 if auth.uid()is null then raise exception 'Access denied'using errcode='42501';end if;
 with finance as materialized(select f.*from private.hub_transport_leader_facts_v2(p_tenant,df,dt,p_user)f
 where(p_months is null or extract(month from occurred_on)::int=any(p_months))and(p_group is null or coalesce(nullif(business_group,''),'Ej klassificerat')=p_group)),
 refs as materialized(select distinct f.unit_id,f.original->>'time_report_id' id from finance f where f.source='TransPA'and f.category='personnel'and f.original->>'time_report_id'is not null),
 links as materialized(select f.original->>'time_report_id' id,count(distinct f.unit_id)=1 and bool_and(f.unit_id is not null)unambiguous
 from private.hub_kpi_prepared_display_facts f where f.tenant_id=p_tenant and f.generation_id=g and f.source='TransPA'and f.category='personnel'
 and f.original->>'time_report_id'in(select id from refs)group by 1),
 time_rows as materialized(select r.unit_id,r.id,min(t.work_date)work_date,min(t.work_hours)hours,
 bool_and(l.unambiguous)and min(t.work_hours)=max(t.work_hours)and min(t.work_hours)>=0 and min(t.work_date)=max(t.work_date)valid
 from refs r join links l using(id)left join private.hub_kpi_prepared_kpi_transpa_time_facts t on t.tenant_id=p_tenant and t.generation_id=g and t.time_report_id=r.id
 and t.work_date between df and dt and(p_months is null or extract(month from t.work_date)::int=any(p_months))group by r.unit_id,r.id),
 unit_time as(select unit_id,case when bool_and(coalesce(valid,false))then sum(hours)end hours,
 min(work_date)first_time_date,max(work_date)through,count(*)reports,count(*)filter(where not coalesce(valid,false))uncertain_reports,
 count(distinct work_date)registered_days from time_rows group by unit_id),
 amounts as(select t.unit_id,sum(f.amount)filter(where f.kind='revenue')revenue,sum(f.amount)filter(where f.kind='cost')cost
 from unit_time t left join finance f on f.unit_id=t.unit_id and f.occurred_on between df and t.through group by t.unit_id),
 projected as(select t.unit_id,jsonb_build_object('source','TransPA','generation',g,'from',df,'to',t.through,'first_time_date',t.first_time_date,
 'worked_hours',round(t.hours,2),'revenue_per_hour',round(a.revenue/nullif(t.hours,0),2),'cost_per_hour',round(a.cost/nullif(t.hours,0),2),
 'matched_revenue',round(a.revenue,2),'matched_cost',round(a.cost,2),'reports',t.reports,'registered_days',t.registered_days,
 'uncertain_reports',t.uncertain_reports,'complete',t.through>=dt,
 'basis','Registrerade TransPA-arbetstimmar, räknade en gång via publicerad entydig enhetskoppling. Belopp avser samma datumurval. Saknad tid uppskattas inte.')value
 from unit_time t left join amounts a on a.unit_id=t.unit_id)
 select jsonb_set(p_report,'{units}',coalesce((select jsonb_agg(u||jsonb_build_object('time_metrics',coalesce(p.value,jsonb_build_object('source','TransPA','worked_hours',null,'revenue_per_hour',null,'cost_per_hour',null,'reason','Entydigt kopplad TransPA-arbetstid saknas i urvalet.')))order by ord)
 from jsonb_array_elements(p_report->'units')with ordinality r(u,ord)left join projected p on p.unit_id=(u->>'unit_id')::uuid),'[]'))into answer;
 return answer;
end $f$;
revoke all on function private.hub_foreman_time_cards_v1(uuid,jsonb,uuid,integer[],text)from public,anon,authenticated;

do $hook$
declare definition text;needle text:=' return private.hub_foreman_mileage_v1(p_tenant,output,p_user,p_months,p_group);';
begin
 select pg_get_functiondef('public.hub_transport_leader_scorecard_v4(uuid,date,date,uuid,uuid,integer,integer[],text)'::regprocedure)into definition;
 if strpos(definition,'hub_foreman_time_cards_v1')=0 then
  if strpos(definition,needle)=0 then raise exception 'Unexpected scorecard definition';end if;
  execute replace(definition,needle,' output:=private.hub_foreman_mileage_v1(p_tenant,output,p_user,p_months,p_group);'||chr(10)||' return private.hub_foreman_time_cards_v1(p_tenant,output,p_user,p_months,p_group);');
 end if;
end $hook$;
notify pgrst,'reload schema';