-- Shared project 10818 needs explicit job evidence, never a generic saw keyword.
create or replace function private.hub_saw_cost_evidence_v1(p_tenant uuid,p_generation uuid,p_original jsonb)
returns jsonb language sql stable security definer set search_path='' as $$
 with evidence as(select concat_ws(' ',p_original->>'Kommentar',p_original->>'Kommentarer',p_original->>'Beskrivning',p_original->>'comment',p_original->>'description',p_original->>'Verifikationstext',p_original->>'AO/ÄTA-benämning')txt),
 refs as(select distinct m[1]order_number from evidence cross join lateral regexp_matches(txt,'(?:arbetsorder|workify|order|ao)[[:space:]#:.nr-]*([0-9]{3,})','gi')m),
 verified as(select r.order_number,min(f.fact_id)source_fact_id from refs r join private.hub_kpi_prepared_facts f
 on f.tenant_id=p_tenant and f.generation_id=p_generation and f.source='Workify' and f.kind='revenue' and f.original->>'Ordernummer'=r.order_number
 where f.original->>'Artikelnummer'='12-04' or f.original->>'Artikelnamn'~*'^extra[[:space:]]+såggubbe([[:space:]]|$)' group by r.order_number)
 select case when (select count(*)from refs)>0 and(select count(*)from refs)=(select count(*)from verified)
 then jsonb_build_object('basis','verified_workify_order_reference','matches',(select jsonb_agg(to_jsonb(v))from verified v))
 when trim(txt)~*'^extra[[:space:]]+såggubbe([[:space:]:,.-]|$)' then jsonb_build_object('basis','explicit_extra_saw_operator','text',txt)
 end from evidence;
$$;
revoke all on function private.hub_saw_cost_evidence_v1(uuid,uuid,jsonb)from public,anon,authenticated;
do $$declare d text;old text:=$old$concat_ws(' ',f.description,f.original->>'Verifikationstext',f.original->>'AO/ÄTA-benämning',f.original->>'Beskrivning')~*'(sågning|trädfäll|kransåg|beskärning)'$old$;begin
 d:=pg_get_functiondef('private.hub_apply_saw_activity_v1(uuid,uuid)'::regprocedure);
 if position(old in d)=0 then raise exception 'Saw evidence rule changed';end if;
 d:=replace(d,old,'private.hub_saw_cost_evidence_v1(p_tenant,p_generation,f.original) is not null ');
 d:=replace(d,$old$'share',share);$old$,$new$'share',share,'verified_evidence',case when why='saw_evidence_on_shared_project' then private.hub_saw_cost_evidence_v1(p_tenant,p_generation,f.original)end);$new$);
 execute d;
end $$;
