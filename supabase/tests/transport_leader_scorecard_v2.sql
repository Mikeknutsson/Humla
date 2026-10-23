-- Run in an isolated transaction after the migration; fixtures are rolled back.
begin;
do $$
declare tenant uuid;owner_id uuid;unit uuid;g uuid;r jsonb;expected numeric;actual numeric;blocked boolean;
begin
 select m.tenant_id,m.user_id,s.active_generation into strict tenant,owner_id,g
 from public.hub_tenant_members m join private.hub_kpi_report_state s on s.tenant_id=m.tenant_id
 where m.role='owner' and m.status='active' and s.active_generation is not null limit 1;
 perform set_config('request.jwt.claim.sub',owner_id::text,true);
 select f.unit_id into strict unit from private.hub_kpi_prepared_display_facts f
 join public.hub_objects o on o.id=f.unit_id and o.object_type='EconomicUnit'
 where f.generation_id=g and f.tenant_id=tenant and f.cost_center='30' and f.kind='revenue'
 and f.occurred_on between '2026-09-01' and '2026-09-30' limit 1;
 r:=public.hub_transport_leader_scorecard_v2(tenant,'2026-09-01','2026-09-30');
 select sum(case when kind='revenue' then amount else 0 end) into expected from private.hub_kpi_prepared_display_facts f
 where f.generation_id=g and f.tenant_id=tenant and f.cost_center='30' and f.occurred_on between '2026-09-01' and '2026-09-30'
 and not coalesce((f.original->>'_humla_excluded_from_kpi')::boolean,false);
 if (r#>>'{summary,revenue}')::numeric is distinct from expected then raise exception 'Published revenue mismatch';end if;
 r:=public.hub_transport_leader_scorecard_v2(tenant,'2026-09-01','2027-08-31',null,null,0,array[9]);
 if (r#>>'{summary,revenue}')::numeric is distinct from expected then raise exception 'Saved month scope mismatch';end if;
 perform public.hub_transport_unit_target_save_v2(tenant,unit,'2026-09-01',4,'Regression first target');
 perform public.hub_transport_unit_target_save_v2(tenant,unit,'2026-09-16',10,'Regression revised target');
 r:=public.hub_transport_leader_scorecard_v2(tenant,'2026-09-01','2026-09-30',null,unit);
 select sum(f.amount*case when f.occurred_on<'2026-09-16' then 0.04 else 0.10 end) into expected
 from private.hub_transport_leader_facts_v2(tenant,'2026-09-01','2026-09-30',null) f where f.unit_id=unit and f.kind='revenue';
 actual:=(r#>>'{units,0,target_result}')::numeric;
 if actual is distinct from expected then raise exception 'Dated weighted target mismatch';end if;
 blocked:=false;
 begin perform public.hub_transport_unit_target_save_v2(tenant,unit,'2026-09-16',20,'Duplicate target');exception when others then blocked:=true;end;
 if not blocked then raise exception 'Overlapping target accepted';end if;
 insert into public.hub_transport_leader_units(tenant_id,user_id,unit_id,valid_from,valid_to,assigned_by)
 values(tenant,owner_id,unit,'2026-09-10','2026-09-15',owner_id);
 r:=public.hub_transport_leader_scorecard_v2(tenant,'2026-09-01','2026-09-30',owner_id,unit);
 select coalesce(sum(amount)filter(where kind='revenue'),0) into expected from private.hub_transport_leader_facts_v2(tenant,'2026-09-10','2026-09-15',null) f where f.unit_id=unit;
 actual:=(r#>>'{summary,revenue}')::numeric;
 if actual is distinct from expected then raise exception 'Handover leaked full month';end if;
 update public.hub_tenant_members set role='supervisor' where tenant_id=tenant and user_id=owner_id;
 r:=public.hub_transport_leader_scorecard_v2(tenant,'2026-09-01','2026-09-30',null,unit);
 if (r#>>'{summary,revenue}')::numeric is distinct from expected then raise exception 'Non-owner saw unassigned facts';end if;
 blocked:=false;
 begin perform public.hub_transport_leader_scorecard_v2(tenant,'2026-09-01','2026-09-30',gen_random_uuid());exception when insufficient_privilege then blocked:=true;end;
 if not blocked then raise exception 'Cross-user access accepted';end if;
 perform set_config('request.jwt.claim.sub','',true);
 blocked:=false;
 begin perform public.hub_transport_leader_scorecard_v2(tenant,'2026-09-01','2026-09-30');exception when others then blocked:=true;end;
 if not blocked then raise exception 'Unauthenticated access accepted';end if;
 raise notice 'Published totals, weighted targets, overlap rejection, handover dates and authorization passed';
end $$;
rollback;
