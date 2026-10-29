begin;set local jit=off;set local statement_timeout='25s';
select set_config('request.jwt.claim.sub','5a6fa4c4-5427-47fa-9835-d997fe81c7d5',true);
do $test$ declare t uuid:='944597b6-9c46-4bef-998d-f19e23c4245b';g uuid;a jsonb;b jsonb;v numeric;before_cost numeric;after_cost numeric;baseline text;after_rows text;
begin
select active_generation into g from private.hub_kpi_report_state where tenant_id=t;
select sum(amount)filter(where kind='cost'),md5(string_agg(to_jsonb(f)::text,'' order by fact_id)filter(where not(original?'_humla_saw_chip'))) into before_cost,baseline from private.hub_kpi_prepared_facts f where tenant_id=t and generation_id=g;
perform private.hub_saw_material_value_v1(t,g);
select sum(amount)filter(where kind='cost'),md5(string_agg(to_jsonb(f)::text,'' order by fact_id)filter(where not(original?'_humla_saw_chip'))) into after_cost,after_rows from private.hub_kpi_prepared_facts f where tenant_id=t and generation_id=g;
if before_cost is distinct from after_cost or baseline is distinct from after_rows then raise exception 'Nonmaterial facts changed';end if;
a:=public.hub_transport_leader_scorecard_v4(t,'2026-09-01','2026-10-29','bc566ca4-dc80-4d81-a7dc-1378eec7bb93');
if (a#>>'{saw_breakdown,material_revenue}')::numeric<>20160 then raise exception 'Current material value';end if;
if (a#>>'{saw_breakdown,management_cost}')::numeric+(a#>>'{saw_breakdown,other_cost}')::numeric<>(a#>>'{summary,cost}')::numeric then raise exception 'Cost reconciliation';end if;
b:=public.hub_foreman_result_trend_v1(t,'2026-09-01','2026-10-29','bc566ca4-dc80-4d81-a7dc-1378eec7bb93');
if (a#>>'{summary,result}')::numeric<>(b#>>'{latest,result}')::numeric then raise exception 'Trend reconciliation';end if;
perform private.hub_saw_material_value_v1(t,g);
b:=public.hub_transport_leader_scorecard_v4(t,'2026-09-01','2026-10-29','bc566ca4-dc80-4d81-a7dc-1378eec7bb93');
if a is distinct from b then raise exception 'Replay changed report';end if;
select sum(amount)into v from private.hub_kpi_prepared_facts where tenant_id=t and generation_id=g and fiscal_year=2025 and original?'_humla_saw_chip';
if v<>519450 then raise exception 'Historical approved weigh value';end if;
if exists(select 1 from private.hub_kpi_prepared_facts where tenant_id=t and generation_id=g and original?'_humla_saw_chip' group by fact_id having count(*)>1)then raise exception 'Duplicate material fact';end if;
if exists(select 1 from private.hub_kpi_prepared_facts f left join private.hub_kpi_prepared_display_facts d using(tenant_id,generation_id,fact_id)
where f.tenant_id=t and f.generation_id=g and f.original?'_humla_saw_chip' and f.amount is distinct from d.amount)then raise exception 'Display mismatch';end if;
a:=public.hub_transport_leader_scorecard_v4(t,'2026-09-01','2026-10-29','bc566ca4-dc80-4d81-a7dc-1378eec7bb93',null,0,array[9]);
if (a#>>'{saw_breakdown,material_revenue}')::numeric<>0 then raise exception 'Month leakage';end if;
perform set_config('request.jwt.claim.sub','bc566ca4-dc80-4d81-a7dc-1378eec7bb93',true);
a:=public.hub_transport_leader_scorecard_v4(t,'2026-09-01','2026-10-29','bc566ca4-dc80-4d81-a7dc-1378eec7bb93');
if (a#>>'{saw_breakdown,material_revenue}')::numeric<>20160 then raise exception 'Own read';end if;
begin
 perform public.hub_transport_leader_scorecard_v4(t,'2026-09-01','2026-10-29','6bee2e13-a6c7-4a05-b22f-9f91f5424a31');
 raise exception 'Cross profile allowed';
exception when insufficient_privilege then null;end;
end $test$;
select 'PASS: conservation, replay, 600/ton, monthly scope, display, trend, own read, cross-profile denial' result;rollback;