create or replace function public.hub_kpi_ai_snapshot_v1(p_item jsonb) returns jsonb language sql immutable set search_path='' as $f$
 select jsonb_build_object('rows',p_item->'rows','amount',p_item->'amount','first_date',p_item->'first_date','last_date',p_item->'last_date','missing',p_item->'missing','reasons',p_item->'reasons','held',p_item->'held','current_cost_centers',p_item->'current_cost_centers','current_groups',p_item->'current_groups','current_units',p_item->'current_units','current_categories',p_item->'current_categories','samples',p_item->'samples')
$f$;
revoke all on function public.hub_kpi_ai_snapshot_v1(jsonb) from public,anon;
grant execute on function public.hub_kpi_ai_snapshot_v1(jsonb) to authenticated;
create or replace function public.hub_kpi_ai_resolve_v1(p_tenant_id uuid,p_proposal_id uuid,p_action text) returns jsonb language plpgsql set search_path='' as $f$
declare proposal public.kpi_ai_mapping_proposals; queue jsonb; fresh jsonb; applied jsonb;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.manage') then raise exception 'KPI-administratör krävs' using errcode='42501';end if;
 if p_action not in ('approve','reject') then raise exception 'Ogiltig åtgärd';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||':kpi-matching',0));
 select * into proposal from public.kpi_ai_mapping_proposals where id=p_proposal_id and tenant_id=p_tenant_id for update;
 if not found then raise exception 'Förslaget saknas';end if;
 if proposal.status='approved' then return proposal.result||jsonb_build_object('already_approved',true);end if;
 if p_action='reject' then update public.kpi_ai_mapping_proposals set status='rejected',resolved_by=auth.uid(),resolved_at=now() where id=proposal.id;return jsonb_build_object('rejected',true);end if;
 if proposal.status<>'pending' or proposal.confidence<0.55 or proposal.targets='{}'::jsonb then raise exception 'Underlaget behöver kompletteras innan det kan godkännas';end if;
 queue:=public.hub_kpi_match_queue_v2(p_tenant_id,proposal.report_from,proposal.report_to,proposal.queue_dimension,proposal.item->>'reference_type',proposal.item->>'reference',0);
 select i into fresh from jsonb_array_elements(queue->'items')i where i->>'source'=proposal.item->>'source' and i->>'kind'=proposal.item->>'kind' and i->>'reference_type'=proposal.item->>'reference_type' and i->>'reference'=proposal.item->>'reference';
 if fresh is null or public.hub_kpi_ai_snapshot_v1(fresh) is distinct from proposal.snapshot then raise exception 'Underlaget har ändrats. Hämta ett nytt förslag.';end if;
 applied:=public.hub_kpi_match_changes_v1(p_tenant_id,jsonb_build_array(jsonb_build_object('item',proposal.item,'targets',proposal.targets,'valid_from',proposal.valid_from,'valid_to',proposal.valid_to)),proposal.report_from,proposal.report_to,'Godkänt AI-förslag: '||left(proposal.reason,800),false);
 update public.kpi_ai_mapping_proposals set status='approved',resolved_by=auth.uid(),resolved_at=now(),result=applied where id=proposal.id;
 return applied||jsonb_build_object('approved',true);
end $f$;
revoke all on function public.hub_kpi_ai_resolve_v1(uuid,uuid,text) from public,anon;
grant execute on function public.hub_kpi_ai_resolve_v1(uuid,uuid,text) to authenticated;
