-- Set a 20% Hub fallback; explicit unit/group/area targets retain precedence.
DO $defaults$
declare f record; revised text;
begin
 for f in select p.oid,p.proname,pg_get_functiondef(p.oid) definition
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.proname in ('hub_transport_leader_scorecard_v2','hub_transport_leader_scorecard_v3','hub_transport_leader_scorecard_v4','hub_foreman_result_trend_v1')
 loop
 revised:=replace(replace(replace(f.definition,
 'select f.*,t.margin_percent from facts f','select f.*,coalesce(t.margin_percent,20::numeric) margin_percent from facts f'),
 'coalesce(t.margin_percent,g.margin_percent) margin_percent','coalesce(t.margin_percent,g.margin_percent,20::numeric) margin_percent'),
 'coalesce(area_goal,t.margin_percent,g.margin_percent) target','coalesce(area_goal,t.margin_percent,g.margin_percent,20::numeric) target');
 if revised=f.definition and f.definition not like '%20::numeric%' then raise exception 'Unexpected target definition: %',f.proname;end if;
 if revised<>f.definition then execute revised;end if;
 end loop;
end $defaults$;
