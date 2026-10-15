-- Cumulative source statements are evidence, not invented dated invoice facts.
create table if not exists private.hub_project_revenue_statements(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,
 project_id uuid not null,observed_on date not null,billed_total numeric(18,2) not null,
 currency text not null default 'SEK' check(currency='SEK'),vat_basis text not null default 'exclusive' check(vat_basis='exclusive'),
 source_key text not null,source jsonb not null,approved_by uuid not null,created_at timestamptz not null default now(),
 unique(tenant_id,project_id,source_key),foreign key(project_id) references public.hub_objects(id),
 check(billed_total::text not in('NaN','Infinity','-Infinity'))
);
alter table private.hub_project_revenue_statements enable row level security;
revoke all on private.hub_project_revenue_statements from public,anon,authenticated;
create or replace function public.hub_project_revenue_statement_v1(p_tenant_id uuid,p_project_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' set jit='off' as $$
declare s private.hub_project_revenue_statements;generation uuid;imported numeric;answer jsonb;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read') then
  raise exception 'KPI access required' using errcode='42501';end if;
 select * into s from private.hub_project_revenue_statements where tenant_id=p_tenant_id and project_id=p_project_id
 order by observed_on desc,created_at desc limit 1;
 if not found then return null;end if;
 select active_generation into generation from private.hub_kpi_report_state where tenant_id=p_tenant_id;
 select coalesce(sum(f.amount),0) into imported from private.hub_kpi_prepared_facts f
 where f.tenant_id=p_tenant_id and f.generation_id=generation and f.kind='revenue' and f.source='NEXT'
 and f.occurred_on<=s.observed_on and f.project in(select k.identity_value from public.hub_identity_keys k
  where k.tenant_id=p_tenant_id and k.object_id=p_project_id and k.identity_type='next_project_number' and k.confidence=1);
 answer:=jsonb_build_object('id',s.id,'observed_on',s.observed_on,'billed_total',s.billed_total,
 'imported_next_revenue',imported,'unperiodized_difference',s.billed_total-imported,'source',s.source,
 'basis','Ackumulerad fakturerad projektintäkt enligt NeXT-underlag, exklusive moms. Hela projektet till och med underlagets avläsning, oberoende av valt månadsurval. Totalsumman ersätter inte datumfördelade transaktioner och läggs inte ovanpå importerade intäkter. Differensen kräver fakturadatum för periodfördelning. Inga månads-, års- eller betalningsbelopp ändras av detta kontrollunderlag.');
 return answer;
end $$;
revoke all on function public.hub_project_revenue_statement_v1(uuid,uuid) from public,anon;
grant execute on function public.hub_project_revenue_statement_v1(uuid,uuid) to authenticated;
