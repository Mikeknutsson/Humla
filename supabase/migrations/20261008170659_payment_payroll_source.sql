-- Aggregate the existing allocated Hub TransPA facts once; remove only the
-- default employer-cost load used by that snapshot. Never infer net pay or KST.
create or replace function private.hub_payment_payroll_source_v1(p_tenant_id uuid,p_as_of date)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $$
declare gen uuid;synced timestamptz;cfg public.kpi_personnel_salary_settings;load numeric;answer jsonb;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.manage') then raise exception 'Not authorized' using errcode='42501';end if;
 if p_as_of is null or p_as_of<'2000-01-01' or p_as_of>'2100-12-31' then raise exception 'Invalid date';end if;
 select active_generation,synced_at into gen,synced from private.hub_kpi_report_state where tenant_id=p_tenant_id;
 if gen is null then raise exception 'Prepared report unavailable';end if;
 if (select count(*) from public.kpi_personnel_salary_settings where tenant_id=p_tenant_id and is_default)<>1 then
  return jsonb_build_object('synced_at',synced,'settings_match',false,'rows','[]'::jsonb,'reason','Löneschablon saknas eller är motstridig');
 end if;
 select * into cfg from public.kpi_personnel_salary_settings where tenant_id=p_tenant_id and is_default;
 if cfg.updated_at>synced then return jsonb_build_object('synced_at',synced,'settings_match',false,'rows','[]'::jsonb,'reason','Löneinställningarna har ändrats efter Hub-synkningen');end if;
 load:=1+(coalesce(cfg.employer_contribution_pct,31.42)+coalesce(cfg.pension_pct,4.5)+coalesce(cfg.other_overhead_pct,0))/100;
 if load<=0 then raise exception 'Invalid payroll load';end if;
 with facts as materialized(
  select cost_center,occurred_on,amount,original->>'time_report_id' report_id
  from private.hub_kpi_prepared_facts where generation_id=gen and tenant_id=p_tenant_id
   and source='TransPA' and kind='cost' and occurred_on between p_as_of-800 and p_as_of
 ), monthly as (
  select cost_center center,date_trunc('month',occurred_on)::date work_month,
   round(sum(amount)/load,2) gross,count(distinct occurred_on) days,count(distinct report_id) reports,
   min(occurred_on) first_date,max(occurred_on) last_date
  from facts group by 1,2
 )
 select jsonb_build_object('synced_at',synced,'settings_match',true,
 'settings',jsonb_build_object('monthly_salary',cfg.monthly_salary,'weekly_hours',cfg.weekly_hours,'overtime_multiplier',cfg.overtime_multiplier,'removed_load',load),
 'rows',coalesce((select jsonb_agg(jsonb_build_object('center',center,'month',work_month,'gross',gross,'days',days,'reports',reports,'firstDate',first_date,'lastDate',last_date) order by center,work_month) from monthly),'[]'::jsonb)) into answer;
 return answer;
end $$;
revoke all on function private.hub_payment_payroll_source_v1(uuid,date) from public,anon,authenticated;
grant execute on function private.hub_payment_payroll_source_v1(uuid,date) to authenticated;
create or replace function public.hub_payment_payroll_source_v1(p_tenant_id uuid,p_as_of date)
returns jsonb language sql security invoker set search_path=pg_catalog set statement_timeout='45s' as $$
 select private.hub_payment_payroll_source_v1(p_tenant_id,p_as_of)
$$;
revoke all on function public.hub_payment_payroll_source_v1(uuid,date) from public,anon,authenticated;
grant execute on function public.hub_payment_payroll_source_v1(uuid,date) to authenticated;
notify pgrst,'reload schema';
