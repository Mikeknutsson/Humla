-- Reuse confirmed Hub identities; article carrier, not category, decides routing.
create function private.hub_apply_workify_name_rules_v2(p_tenant_id uuid) returns integer
language plpgsql security definer set search_path='' as $fn$
declare changed integer; batches uuid[];
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.manage') then raise exception 'Behörighet saknas' using errcode='42501'; end if;
 with updated as (
  update public.kpi_import_rows r set allocation=coalesce(r.allocation,'{}')
  where r.tenant_id=p_tenant_id and r.data_kind='revenue' and r.source_data ? 'Ordernummer' and r.amount<>0
   and r.vehicle_object_id is null and nullif(trim(r.vehicle_registration),'') is null
   and nullif(trim(r.source_data->>'RegNr'),'') is null and nullif(trim(r.source_data->>'Fordon'),'') is null
   and coalesce(r.allocation->>'manual_override','false')<>'true' and coalesce(r.allocation->>'target','') not in ('project','ignored')
   and exists(select 1 from private.hub_workify_name_vehicle_rules n where n.tenant_id=p_tenant_id
    and n.name_key=lower(regexp_replace(trim(coalesce(nullif(trim(r.source_data->>'Tilldelad'),''),r.source_data->>'Förare')),'[[:space:]]+',' ','g'))
    and r.occurred_on between n.valid_from and coalesce(n.valid_to,'infinity'::date))
   and (select a.target_type='vehicle' and a.revenue_category<>'ignored' from public.kpi_workify_article_rules a
    where a.tenant_id=p_tenant_id and a.enabled and a.article_number=r.source_data->>'Artikelnummer'
    and r.occurred_on between a.valid_from and coalesce(a.valid_to,'infinity'::date) order by a.valid_from desc limit 1)
  returning r.batch_id
 ) select count(*),array_agg(distinct batch_id) into changed,batches from updated;
 update public.kpi_import_batches b set valid_row_count=s.valid,invalid_row_count=s.invalid,
  status=case when s.invalid=0 then 'completed' else 'needs_review' end,
  error_summary=s.errors
 from (select batch_id,count(*)filter(where is_valid) valid,count(*)filter(where not is_valid) invalid,
  coalesce(jsonb_agg(jsonb_build_object('row',row_number,'errors',validation_errors) order by row_number) filter(where not is_valid),'[]') errors
  from public.kpi_import_rows where tenant_id=p_tenant_id and batch_id=any(batches) group by batch_id)s
 where b.id=s.batch_id and b.tenant_id=p_tenant_id and b.status in ('completed','needs_review');
 return changed;
end $fn$;
revoke all on function private.hub_apply_workify_name_rules_v2(uuid) from public,anon,authenticated;

do $patch$
declare definition text; previous text; replacement text;
begin
 definition:=pg_get_functiondef('private.hub_workify_name_fallback_v1()'::regprocedure);
 previous:='if not found or article.target_type<>''vehicle'' or article.revenue_category in (''ignored'',''tipp'',''tipping'',''material'') then return new;end if;';
 if strpos(definition,previous)=0 then raise exception 'Unexpected name fallback definition';end if;
 definition:=replace(definition,previous,'if not found or article.target_type<>''vehicle'' or article.revenue_category=''ignored'' then return new;end if;');
 definition:=replace(definition,'-- A supplied registration/vehicle, manual assignment or project carrier always wins.',
  '-- Explicit assignments are immutable to automatic fallback.
 if coalesce(new.allocation->>''manual_override'',''false'')=''true'' or coalesce(new.allocation->>''target'','''') in (''project'',''ignored'') then return new;end if;');
 definition:=replace(definition,'trim(new.source_data->>''Förare'')','trim(coalesce(nullif(trim(new.source_data->>''Tilldelad''),''''),new.source_data->>''Förare''))');
 definition:=replace(definition,'new.vehicle_registration:=label;new.project_reference:=null;',
  'new.vehicle_registration:=case when label=''INHYRDLASTBIL'' then ''LASTBIL'' else label end;new.project_reference:=case when label=''INHYRDLASTBIL'' then ''9009'' else null end;');
 execute definition;

 definition:=pg_get_functiondef('public.hub_workify_name_rules_v1(uuid,text,jsonb)'::regprocedure);
 previous:=substring(definition from strpos(definition,' elsif p_action=''apply'' then') for strpos(definition,' elsif p_action<>''list''')-strpos(definition,' elsif p_action=''apply'' then'));
 if previous is null or length(previous)<50 then raise exception 'Unexpected rule apply definition';end if;
 replacement:=' elsif p_action=''apply'' then
  changed:=private.hub_apply_workify_name_rules_v2(p_tenant_id);
';
 definition:=replace(definition,previous,replacement);
 definition:=replace(definition,' select jsonb_build_object(''rules''',
  ' if p_action=''save'' then changed:=private.hub_apply_workify_name_rules_v2(p_tenant_id);end if;
 select jsonb_build_object(''rules''');
 execute definition;
end $patch$;
