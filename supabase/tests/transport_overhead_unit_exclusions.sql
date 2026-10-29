begin;set local jit=off;set local statement_timeout='50s';
select set_config('request.jwt.claim.sub','5a6fa4c4-5427-47fa-9835-d997fe81c7d5',true);
do $test$ declare t uuid:='944597b6-9c46-4bef-998d-f19e23c4245b';g uuid;b jsonb;a jsonb;sig text;s2 text;begin
select active_generation into g from private.hub_kpi_report_state where tenant_id=t;
select jsonb_agg(to_jsonb(x)order by fiscal_year,kind)into b from(select fiscal_year,kind,sum(amount)amount from private.hub_kpi_prepared_facts where tenant_id=t and generation_id=g group by 1,2)x;
perform private.hub_allocate_saw_supplier_common_v1(t,g);
perform private.hub_apply_monthly_overhead_v1(t,g);
select jsonb_agg(to_jsonb(x)order by fiscal_year,kind)into a from(select fiscal_year,kind,sum(amount)amount from private.hub_kpi_prepared_facts where tenant_id=t and generation_id=g group by 1,2)x;
if a is distinct from b then raise exception 'Company annual totals changed';end if;
if exists(select 1 from private.hub_kpi_prepared_facts f where f.tenant_id=t and f.generation_id=g
and (f.original?'_humla_monthly_overhead' or f.original?'_humla_supplier_common')
and not private.hub_overhead_unit_eligible_v1(t,f.unit_id,f.cost_center,f.occurred_on))then raise exception 'Excluded unit received overhead';end if;
if exists(select 1 from private.hub_kpi_prepared_facts f left join private.hub_kpi_prepared_display_facts d using(tenant_id,generation_id,fact_id)
where f.tenant_id=t and f.generation_id=g and (f.original?'_humla_monthly_overhead' or f.original?'_humla_supplier_common')and row(f.amount,f.unit_id)is distinct from row(d.amount,d.unit_id))then raise exception 'Display mismatch';end if;
select md5(string_agg(concat_ws('|',f.fact_id,f.amount,f.unit_id,f.cost_center),''order by fact_id))into sig from private.hub_kpi_prepared_facts f where tenant_id=t and generation_id=g and (original?'_humla_monthly_overhead' or original?'_humla_supplier_common');
perform private.hub_allocate_saw_supplier_common_v1(t,g);perform private.hub_apply_monthly_overhead_v1(t,g);
select md5(string_agg(concat_ws('|',f.fact_id,f.amount,f.unit_id,f.cost_center),''order by fact_id))into s2 from private.hub_kpi_prepared_facts f where tenant_id=t and generation_id=g and (original?'_humla_monthly_overhead' or original?'_humla_supplier_common');
if sig is distinct from s2 then raise exception 'Replay changed facts';end if;
if not private.hub_overhead_unit_eligible_v1(t,(select unit_id from private.hub_overhead_unit_exclusions_v1 where tenant_id=t and unit_id<>(select material_unit_id from private.hub_kpi_material_separation_settings where tenant_id=t) limit 1),'20',current_date)then raise exception 'KST20 unintentionally excluded';end if;
end $test$;
select 'PASS: excluded units zero overhead, annual totals conserved, display matched, replay stable, KST20 nonmaterial eligibility preserved' result;rollback;