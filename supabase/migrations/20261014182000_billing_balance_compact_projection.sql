-- Compact normalized rows avoid materializing full invoice JSON for every week.
-- Prepared invoice dates were already validated during publication.
create or replace function public.hub_kpi_billing_balance_v1(p_tenant uuid,p_year integer,p_months integer[],p_filters jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable security definer set search_path='' set jit='off' set plan_cache_mode='force_custom_plan' as $$
declare generation uuid;revision integer;months integer[];answer jsonb;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant,'kpi.read') then
  raise exception 'KPI access required' using errcode='42501';end if;
 months:=private.hub_kpi_month_scope_v1(p_year,p_months);
 if p_filters is null or jsonb_typeof(p_filters)<>'object' or length(p_filters::text)>2000
 or exists(select 1 from jsonb_object_keys(p_filters) k where k not in('cost_center','group','unit','vehicle','project'))then
  raise exception 'Unsupported balance filter';end if;
 select active_generation,correction_revision into generation,revision
 from private.hub_kpi_report_state where tenant_id=p_tenant;
 if generation is null then raise exception 'Prepared report required';end if;
 with dates as materialized(
  select d::date date from generate_series(make_date(p_year,9,1),make_date(p_year+1,8,31),interval '1 day')d
  where extract(month from d)::integer=any(months)
 ),facts as materialized(
  select f.fact_id,f.kind,f.amount,f.occurred_on,
   (f.original->>'Orderstatus'='Invoiced') invoiced,
   case when f.kind='revenue' then (f.display_original#>>'{_humla_invoice,invoice_date}')::date end invoice_date,
   (f.account is distinct from '7010' and not private.hub_ps_own_tank_source_v1(f.original,f.account)) cost_eligible,
   case when kind='revenue' then coalesce(original->>'Kundnamn','') ~* '^elleholms[[:space:]]+maskin'
    else coalesce(original->>'Leverantör','') ~* '^elleholms[[:space:]]+maskin'
     or coalesce(original->>'Verifikation nr','') ~ '^(AO[.]|ARB[.]|NEXT[.](AO|ARB))' end internal,
   case when kind='revenue' then nullif(trim(original->>'Kundnamn'),'')
    else nullif(trim(original->>'Leverantör'),'') end party
  from private.hub_kpi_prepared_facts f where f.tenant_id=p_tenant and f.generation_id=generation
   and ((f.source='Workify' and f.kind='revenue') or (f.source='NEXT' and f.kind='cost'))
   and (f.occurred_on between (select min(date) from dates) and (select max(date) from dates)
    or (f.kind='revenue' and f.display_original#>>'{_humla_invoice,invoice_date}'
     between (select min(date)::text from dates) and (select max(date)::text from dates)))
   and (not(p_filters?'cost_center') or f.cost_center=any(string_to_array(p_filters->>'cost_center',',')))
   and (not(p_filters?'group') or f.business_group=any(string_to_array(p_filters->>'group',',')))
   and (not(p_filters?'unit') or f.unit_id::text=p_filters->>'unit')
   and (not(p_filters?'vehicle') or f.vehicle=p_filters->>'vehicle')
   and (not(p_filters?'project') or f.project=p_filters->>'project')
 ),eligible as materialized(
  select *,case when kind='revenue' then invoice_date else occurred_on end balance_date
  from facts where not internal and party is not null
   and ((kind='revenue' and invoiced is true and invoice_date is not null)
    or (kind='cost' and cost_eligible))
 ),selected as materialized(select e.* from eligible e join dates d on d.date=e.balance_date),
 weekly as(
  select date_trunc('week',d.date)::date week_start,min(d.date) selected_from,max(d.date) selected_to,
   coalesce(sum(e.amount)filter(where e.kind='revenue'),0) invoiced,
   coalesce(sum(e.amount)filter(where e.kind='cost'),0) cost,count(e.fact_id) rows
  from dates d left join selected e on e.balance_date=d.date group by 1
 ),running as(
  select *,invoiced-cost balance,sum(invoiced-cost)over(order by week_start) cumulative_balance,
   to_char(week_start,'IYYY-"V"IW') week from weekly
 ),totals as(
  select coalesce(sum(amount)filter(where kind='revenue'),0) invoiced,
   coalesce(sum(amount)filter(where kind='cost'),0) cost,count(*) rows,max(balance_date) latest_date from selected
 )select jsonb_build_object('generation',generation,'correction_revision',revision,
  'status',case when t.rows=0 then 'no_data' else 'ready' end,
  'invoiced',case when t.rows>0 then t.invoiced end,'cost',case when t.rows>0 then t.cost end,
  'balance',case when t.rows>0 then t.invoiced-t.cost end,'latest_date',t.latest_date,
  'gauge_position',case when t.rows>0 then greatest(0,least(100,50+50*(t.invoiced-t.cost)/greatest(abs(t.invoiced)+abs(t.cost),1))) end,
  'internal_included',false,'currency','SEK','vat_included',false,
  'weeks',(select jsonb_agg(to_jsonb(w)order by week_start)from running w),
  'pending_invoice',(select jsonb_build_object('rows',count(*),'amount',coalesce(sum(f.amount),0))
   from facts f join dates d on d.date=f.occurred_on where f.kind='revenue' and not f.internal and f.party is not null
    and (f.invoiced is not true or f.invoice_date is null)),
  'unknown_party',(select jsonb_build_object('rows',count(*),'amount',coalesce(sum(abs(f.amount)),0))
   from facts f join dates d on d.date=f.occurred_on where f.party is null),
  'basis','Fakturerat i Workify efter fakturadatum minus externa NeXT-kostnader efter bokföringsdatum. Exklusive moms. Interna överföringar, intern tid, lön på konto 7010 och egentanksförbrukning ingår inte. Saknad motpart räknas separat. Avskrivning och TransPA-schablon är inte externa fakturakostnader. Visar faktureringsförsprång, inte betalningsdag eller banksaldo.') into answer from totals t;
 return answer;
end $$;
revoke all on function public.hub_kpi_billing_balance_v1(uuid,integer,integer[],jsonb) from public,anon;
grant execute on function public.hub_kpi_billing_balance_v1(uuid,integer,integer[],jsonb) to authenticated;
