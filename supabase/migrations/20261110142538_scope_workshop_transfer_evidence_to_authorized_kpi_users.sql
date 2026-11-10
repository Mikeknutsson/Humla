create function private.hub_internal_workshop_transfer_rows_v1(p_tenant_id uuid,p_from date,p_to date,p_months integer[])
returns jsonb language plpgsql stable security definer set search_path to '' as $function$
declare workshop_rows jsonb;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read') then
  raise exception 'KPI access required' using errcode='42501';
 end if;
 select coalesce(jsonb_agg(jsonb_build_object(
  'source_key','next-workshop:'||f.fact_id,'row_id',f.fact_id,'occurred_on',f.occurred_on,
  'order',f.original->>'AO/ÄTA','project',f.project,'source_center','40','receiver_center',c.center,
  'category','workshop','amount',f.amount,'article','4630','description',f.description,
  'ready',false,'invoiced',false,'status','review',
  'review_reason',case when c.center is null then 'Projektets kostnadsställe saknas eller är tvetydigt' else 'NEXT konto 4630 – underlag för avstämning' end
 )),'[]') into workshop_rows
 from private.hub_kpi_report_facts_v1 f
 join private.hub_kpi_report_state s on s.tenant_id=f.tenant_id and s.active_generation=f.generation_id
 left join lateral (
  select case when count(distinct p.cost_center)=1 then min(p.cost_center) end center
  from public.kpi_project_classification_periods p
  where p.tenant_id=f.tenant_id and p.project_reference=f.project
   and p.valid_from<=f.occurred_on and (p.valid_to is null or p.valid_to>=f.occurred_on)
 ) c on true
 where f.tenant_id=p_tenant_id and f.source='NEXT' and f.account='4630' and f.kind='cost'
   and f.amount<>0 and f.occurred_on between p_from and p_to
   and (p_months is null or extract(month from f.occurred_on)::integer=any(p_months))
   and (f.original->>'Kontobeskrivning' ilike '%verkstad%' or f.description ilike '%intern AO%')
   and c.center is distinct from '40';
 return workshop_rows;
end $function$;
revoke all on function private.hub_internal_workshop_transfer_rows_v1(uuid,date,date,integer[]) from public;
grant execute on function private.hub_internal_workshop_transfer_rows_v1(uuid,date,date,integer[]) to authenticated;
CREATE OR REPLACE FUNCTION public.hub_kpi_internal_center_summary_v2(p_tenant_id uuid, p_from date, p_to date, p_months integer[] DEFAULT NULL::integer[])
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
 SET statement_timeout TO '45s'
 SET work_mem TO '64MB'
 SET jit TO 'off'
AS $function$
declare workify_rows jsonb; workshop_rows jsonb;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read') then raise exception 'KPI access required' using errcode='42501';end if;
 workify_rows:=public.hub_kpi_internal_transfers_v1(p_tenant_id,p_from,p_to,p_months)->'rows';
 workshop_rows:=private.hub_internal_workshop_transfer_rows_v1(p_tenant_id,p_from,p_to,p_months);
 return private.hub_internal_center_summary_engine_v2(workify_rows||workshop_rows);
end $function$;