-- Integration checks against approved profiles; all test changes roll back.
begin;
select set_config('request.jwt.claim.sub','5a6fa4c4-5427-47fa-9835-d997fe81c7d5',true);
set local statement_timeout='60s';
do $$
declare t uuid:='944597b6-9c46-4bef-998d-f19e23c4245b';g uuid;r jsonb;before_cost numeric;after_cost numeric;expected numeric;actual numeric;sample private.hub_kpi_prepared_facts;
begin
 select active_generation into strict g from private.hub_kpi_report_state where tenant_id=t;
 select sum(amount)into before_cost from private.hub_kpi_prepared_facts where tenant_id=t and generation_id=g;
 r:=private.hub_publish_approved_time_costs_v1(t,g);
 if(r->>'published_profiles')::int<>0 then raise exception 'Repeated publication changed profiles';end if;
 select sum(amount)into after_cost from private.hub_kpi_prepared_facts where tenant_id=t and generation_id=g;
 if before_cost is distinct from after_cost then raise exception 'Repeated publication changed money';end if;
 if exists(select 1 from private.hub_approved_time_cost_basis_v1(t,g)where person_id is null or abs(hours-covered_hours-gap_hours)>0.000001 or abs(gap_hours-regular_hours-overtime_hours)>0.000001)then raise exception 'Person, gap or overtime conservation failed';end if;
 select sum(r.paid_hours)into expected from public.kpi_import_rows r join private.hub_time_cost_profiles p on p.batch_id=r.batch_id and p.tenant_id=t and p.kind='historical_payroll'
 where upper(trim(coalesce(r.source_data->>'Tidkod','')))!~'^OB';
 select sum(hours)into actual from private.hub_approved_time_cost_basis_v1(t,g)where profile_kind='historical_payroll';
 if expected is distinct from actual then raise exception 'Historical physical rows or OB handling changed';end if;
 if exists(select 1 from private.hub_kpi_prepared_facts where tenant_id=t and generation_id=g and source='Verkstadsschablon'and category<>'service_repair')then raise exception 'Workshop estimate outside repair costs';end if;
 -- An actual workshop debit must suppress that project's provisional estimate in the next build basis.
 select * into strict sample from private.hub_kpi_prepared_facts where tenant_id=t and generation_id=g and source='Verkstadsschablon'limit 1;
 insert into private.hub_kpi_prepared_facts select(jsonb_populate_record(null::private.hub_kpi_prepared_facts,to_jsonb(sample)||jsonb_build_object('fact_id','test:actual-workshop-arrived','source','NEXT','account','4630','description','Verkstad','original',jsonb_build_object('Verifikation nr','AO.'||to_char(sample.occurred_on,'YYYY-MM'))))).*;
 if exists(select 1 from private.hub_approved_time_cost_basis_v1(t,g)where profile_kind='missing_workshop_debit'and project=sample.project and date_trunc('month',work_date)=date_trunc('month',sample.occurred_on))then raise exception 'Actual debit did not replace provisional repair';end if;
 if has_function_privilege('anon','private.hub_publish_approved_time_costs_v1(uuid,uuid)','execute')or has_function_privilege('authenticated','private.hub_import_approved_next_time_rows_v1(uuid,uuid,jsonb,text)','execute')then raise exception 'Private write adapter exposed';end if;
end$$;
rollback;
