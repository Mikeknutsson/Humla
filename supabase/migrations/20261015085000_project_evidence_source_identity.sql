CREATE OR REPLACE FUNCTION public.hub_project_revenue_statement_v1(p_tenant_id uuid, p_project_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
 SET jit TO 'off'
AS $function$
declare s private.hub_project_revenue_statements;generation uuid;imported numeric;answer jsonb;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read') then
  raise exception 'KPI access required' using errcode='42501';end if;
 select * into s from private.hub_project_revenue_statements where tenant_id=p_tenant_id and project_id=p_project_id
 order by observed_on desc,created_at desc limit 1;
 if not found then return null;end if;
 select active_generation into generation from private.hub_kpi_report_state where tenant_id=p_tenant_id;
 select coalesce(sum(f.amount),0) into imported from private.hub_kpi_prepared_facts f
 where f.tenant_id=p_tenant_id and f.generation_id=generation and f.kind='revenue' and f.source in('NEXT','Workify')
 and f.occurred_on<=s.observed_on and coalesce(f.project,case when f.source='Workify' then nullif(trim(f.original->>'Projektnr'),'')end) in(select k.identity_value from public.hub_identity_keys k
  where k.tenant_id=p_tenant_id and k.object_id=p_project_id and k.identity_type='next_project_number' and k.confidence=1);
 answer:=jsonb_build_object('id',s.id,'observed_on',s.observed_on,'billed_total',s.billed_total,
 'imported_project_revenue',imported,'unperiodized_difference',s.billed_total-imported,'source',s.source,
 'basis','Ackumulerad fakturerad projektintäkt enligt NeXT-underlag, exklusive moms. Hela projektet till och med underlagets avläsning, oberoende av valt månadsurval. Totalsumman ersätter inte datumfördelade transaktioner och läggs inte ovanpå importerade intäkter. Avstämningsdifferensen visas separat och kan även innehålla avrundning i kontrollunderlaget. Inga månads-, års- eller betalningsbelopp ändras av detta kontrollunderlag.');
 return answer;
end $function$

