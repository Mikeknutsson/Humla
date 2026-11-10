-- Extend the existing project report with a separate company view of paired internal transport.
do $migration$
declare
 definition text := pg_get_functiondef('private.hub_kpi_project_report_v5(uuid,date,date,text,text,uuid,integer,text,text[],integer[])'::regprocedure);
 totals_anchor text := ' ), details as(';
 payload_anchor text := '  ''summary'',(select to_jsonb(t) from totals t),';
begin
 if strpos(definition, totals_anchor)=0 or strpos(definition, payload_anchor)=0 then
  raise exception 'Unexpected project report definition';
 end if;
 definition := replace(definition, totals_anchor, $body$
 ), company_workify as materialized(
  select base.payload->>'project' project_number,
   date_trunc('month', income.date)::date period, sign(income.amount) direction,
   sum(income.amount) amount
  from internal_income income
  join internal_base base on income.id='workify-internal-income:'||base.row_id
  join selected receiver on receiver.project_number=base.payload->>'project'
  where p_center is null and p_manager is null and p_project is null
   and coalesce(cardinality(p_groups),0)=0
   and income.category='transport' and income.amount<>0
  group by 1,2,3
 ), company_next as materialized(
  select entry.project_number, to_date(right(raw.source_data->>'Verifikationstext',7),'YYYY-MM') period,
   sign(entry.amount) direction, round(sum(entry.amount),2) amount
  from next_evidence entry
  join public.kpi_import_rows raw on raw.tenant_id=p_tenant_id and raw.id=entry.id::uuid
  where p_center is null and p_manager is null and p_project is null
   and coalesce(cardinality(p_groups),0)=0
   and entry.kind='cost' and entry.account='4600' and entry.amount<>0
   and raw.source_data->>'Verifikationstext' ~* '^Intern AO [0-9]{4}-(0[1-9]|1[0-2])$'
  group by 1,2,3
 ), company_same_month as materialized(
  select w.project_number,w.direction,w.period workify_period,n.period next_period,w.amount
  from company_workify w join company_next n using(project_number,direction,period,amount)
 ), company_adjacent_candidates as(
  select w.project_number,w.direction,w.period workify_period,n.period next_period,w.amount,
   count(*) over(partition by w.project_number,w.direction,w.period) workify_candidates,
   count(*) over(partition by n.project_number,n.direction,n.period) next_candidates
  from company_workify w join company_next n using(project_number,direction,amount)
  where n.period in ((w.period-interval '1 month')::date,(w.period+interval '1 month')::date)
   and not exists(select 1 from company_same_month m where (m.project_number,m.direction,m.workify_period)=(w.project_number,w.direction,w.period))
   and not exists(select 1 from company_same_month m where (m.project_number,m.direction,m.next_period)=(n.project_number,n.direction,n.period))
 ), company_pairs as materialized(
  select * from company_same_month
  union all
  select project_number,direction,workify_period,next_period,amount
  from company_adjacent_candidates where workify_candidates=1 and next_candidates=1
 ), company_review as(
  select coalesce(w.project_number,n.project_number) project_number,
   coalesce(w.period,n.period) period,coalesce(w.direction,n.direction) direction,
   w.amount workify_amount,n.amount next_amount
  from (select w.* from company_workify w where not exists(
   select 1 from company_pairs m where (m.project_number,m.direction,m.workify_period)=(w.project_number,w.direction,w.period))) w
  full join (select n.* from company_next n where not exists(
   select 1 from company_pairs m where (m.project_number,m.direction,m.next_period)=(n.project_number,n.direction,n.period))) n
  using(project_number,direction,period)
 ), company_totals as(
  select count(*) matched_groups,count(*) filter(where workify_period<>next_period) adjacent_groups,
   coalesce(sum(amount),0) eliminated
  from company_pairs
 ), details as($body$);
 definition := replace(definition, payload_anchor, $payload$
  'company_transport',case when p_center is null and p_manager is null and p_project is null and coalesce(cardinality(p_groups),0)=0 then
   (select to_jsonb(c)||jsonb_build_object('revenue',t.revenue-c.eliminated,'cost',t.cost-c.eliminated,
    'result',t.result,'review',coalesce((select jsonb_agg(to_jsonb(r) order by r.period,r.project_number,r.direction) from company_review r),'[]'::jsonb))
    from company_totals c cross join totals t) end,
  'summary',(select to_jsonb(t) from totals t),$payload$);
 execute definition;
end
$migration$;
