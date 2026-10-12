-- Date-versioned confirmed knowledge uses canonical Hub object IDs.
alter table public.hub_allocation_mapping_rules
 add column if not exists target_object_id uuid references public.hub_objects(id),
 add column if not exists source_family text not null default '*',
 add column if not exists data_kind text not null default '*',
 add column if not exists priority integer not null default 50,
 add column if not exists verified_by uuid,
 add column if not exists verified_at timestamptz,
 add column if not exists reason text;
alter table public.hub_allocation_mapping_rules drop constraint if exists hub_allocation_mapping_rules_evidence_type_check;
alter table public.hub_allocation_mapping_rules add constraint hub_allocation_mapping_rules_evidence_type_check
 check(evidence_type in ('fact','project','supervisor','driver','customer','supplier','account','article','reference','vehicle_registration'));
create table public.hub_allocation_mapping_events(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,rule_id uuid not null references public.hub_allocation_mapping_rules(id),
 actor_id uuid not null,action text not null,created_at timestamptz not null default now(),snapshot jsonb not null);
alter table public.hub_allocation_mapping_events enable row level security;
create policy allocation_events_read on public.hub_allocation_mapping_events for select to authenticated
 using(public.hub_has_permission(tenant_id,'kpi.manage'));
revoke all on public.hub_allocation_mapping_events from public,anon,authenticated;
grant select on public.hub_allocation_mapping_events to authenticated;
-- Writes only through the conflict-checked, audited RPC; no direct client bypass.
revoke insert,update,delete on public.hub_allocation_mapping_rules from authenticated;

create or replace function public.hub_allocation_rule_confirm_v2(p_tenant_id uuid,p_rule jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_variable
declare target_id uuid;target_text text;dimension text:=p_rule->>'dimension';evidence_type text:=p_rule->>'evidenceType';
 evidence text:=upper(trim(p_rule->>'evidenceValue'));family text:=coalesce(p_rule->>'sourceFamily','*');
 kind text:=coalesce(p_rule->>'kind','*');date_from date:=(p_rule->>'from')::date;date_to date:=(p_rule->>'to')::date;
 reason text:=trim(p_rule->>'reason');saved public.hub_allocation_mapping_rules;priority integer;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.manage') then raise exception 'KPI-administratör krävs' using errcode='42501';end if;
 if dimension is null or dimension not in ('vehicle','project','cost_center') or evidence_type is null
 or evidence_type not in ('fact','project','supervisor','driver','customer','supplier','account','article','reference','vehicle_registration')
 or nullif(evidence,'') is null or length(evidence)>500 or date_from is null or date_to<date_from
 or length(coalesce(reason,'')) not between 3 and 1000 or family not in ('*','NEXT','Workify','TransPA') or kind not in ('*','cost','revenue')
 then raise exception 'Kontrollera evidens, period och motivering';end if;
 target_text:=trim(p_rule->>'target');
 if dimension in ('vehicle','project') then
 target_id:=(p_rule->>'targetObjectId')::uuid;
 if target_id is null or not exists(select 1 from public.hub_objects o where o.id=target_id and o.tenant_id=p_tenant_id
 and lower(o.object_type)=case dimension when 'vehicle' then 'vehicle' else 'project' end) then raise exception 'Kanoniskt mål i arbetsytan krävs' using errcode='42501';end if;
 select min(k.identity_value) into target_text from public.hub_identity_keys k where k.tenant_id=p_tenant_id and k.object_id=target_id
 and k.confidence=1 and k.identity_type=case dimension when 'vehicle' then 'registration_number' else 'next_project_number' end;
 if target_text is null then raise exception 'Målet saknar verifierad källidentitet';end if;
 else
 if not exists(select 1 from public.kpi_project_classification_periods c where c.tenant_id=p_tenant_id and c.cost_center=target_text)
 then raise exception 'Okänt kostnadsställe';end if;
 end if;
 priority:=case evidence_type when 'fact' then 0 when 'vehicle_registration' then 10 when 'project' then 20 when 'driver' then 30 else 50 end;
 perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||':hub-allocation-rules',0));
 if exists(select 1 from public.hub_allocation_mapping_rules m where m.tenant_id=p_tenant_id and m.dimension=dimension
 and m.rule_status='confirmed' and m.evidence_type=evidence_type and upper(trim(m.evidence_value))=evidence
 and (m.source_family=family or m.source_family='*' or family='*') and (m.data_kind=kind or m.data_kind='*' or kind='*')
 and daterange(coalesce(m.valid_from,'-infinity'),coalesce(m.valid_to,'infinity'),'[]') && daterange(date_from,coalesce(date_to,'infinity'),'[]')
 and (m.target_object_id is distinct from target_id or m.target_value<>target_text))
 then raise exception 'Motstridig bekräftad regel i överlappande period' using errcode='23505';end if;
 select * into saved from public.hub_allocation_mapping_rules m where m.tenant_id=p_tenant_id and m.dimension=dimension
 and m.rule_status='confirmed' and m.evidence_type=evidence_type and upper(trim(m.evidence_value))=evidence
 and m.source_family=family and m.data_kind=kind and m.valid_from=date_from and m.valid_to is not distinct from date_to
 and m.target_object_id is not distinct from target_id and m.target_value=target_text;
 if found then return to_jsonb(saved);end if;
 insert into public.hub_allocation_mapping_rules(tenant_id,dimension,evidence_type,evidence_value,target_value,target_object_id,
 source_family,data_kind,valid_from,valid_to,priority,confidence,source,verified_by,verified_at,reason,created_by)
 values(p_tenant_id,dimension,evidence_type,evidence,target_text,target_id,family,kind,date_from,date_to,priority,1,'manual_confirmed',auth.uid(),now(),reason,auth.uid()) returning * into saved;
 insert into public.hub_allocation_mapping_events(tenant_id,rule_id,actor_id,action,snapshot)
 values(p_tenant_id,saved.id,auth.uid(),'confirmed',to_jsonb(saved));
 return to_jsonb(saved);
end $$;
revoke all on function public.hub_allocation_rule_confirm_v2(uuid,jsonb) from public,anon;
grant execute on function public.hub_allocation_rule_confirm_v2(uuid,jsonb) to authenticated;
notify pgrst,'reload schema';

