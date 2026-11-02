-- Isolated source fixtures; schema and test imports are rolled back together.
begin;
set local statement_timeout='30s';
set local jit=off;
select set_config('request.jwt.claim.sub','5a6fa4c4-5427-47fa-9835-d997fe81c7d5',true);
create temporary table payment_stena_fixture(
 fact_id text,occurred_on date,kind text,amount numeric,category text,project text,vehicle text,unit_id uuid,unit_name text,business_group text,source text,description text,account text,file_name text,row_number integer,original jsonb,cost_center text,cost_center_name text,classification_source jsonb
) on commit drop;
insert into payment_stena_fixture(fact_id,occurred_on,kind,amount,source,original,cost_center)
values ('fixture-a','2026-10-01','revenue',500,'Workify','{"Kundnamn":"Stena Recycling AB","Littranummer":"99999887"}','30'),
('fixture-b','2026-10-01','revenue',600,'Workify','{"Kundnamn":"Stena Recycling AB","ArtikelKommentar":"99999888"}','30'),
('fixture-other','2026-10-01','revenue',700,'Workify','{"Kundnamn":"Annan kund","Littranummer":"99999887"}','30');
create or replace function private.hub_kpi_filtered_classified_facts_v1(p_tenant_id uuid,p_from date,p_to date,p_filters jsonb default '{}'::jsonb)
returns table(fact_id text,occurred_on date,kind text,amount numeric,category text,project text,vehicle text,unit_id uuid,unit_name text,business_group text,source text,description text,account text,file_name text,row_number integer,original jsonb,cost_center text,cost_center_name text,classification_source jsonb)
language sql stable security definer set search_path='' as $$select * from pg_temp.payment_stena_fixture$$;
do $test$
declare t uuid:='944597b6-9c46-4bef-998d-f19e23c4245b';r jsonb;h text:=repeat('c',64);s text:=repeat('d',64);
begin
 insert into private.hub_stena_files_v1(tenant_id,file_hash,file_name,source_kind,expected_rows)values(t,h,'test-history.xlsx','history',2),(t,s,'test-settled.xlsx','settled',1);
 perform private.hub_stena_ingest_v1(t,h,'[{"row_number":2,"booking":"99999887","date":"2026-10-01","registration":"","price":100,"load_carrier_type":"Pall"},{"row_number":3,"booking":"99999888","date":"2026-10-01","registration":"","price":null,"load_count":2,"load_carrier_type":null}]');
 update private.hub_stena_files_v1 set complete=true where tenant_id=t and file_hash=h;
 r:=public.hub_payment_outcome_source_v1(t,'2026-11-02');
 assert exists(select 1 from jsonb_array_elements(r->'rows')x where x->>'reference'='99999887' and x->>'amountStatus'='history' and (x->>'amount')::numeric=100),'History missing';
 perform private.hub_stena_ingest_v1(t,s,'[{"row_number":2,"booking":"99999887","date":"2026-10-01","registration":"","settled_amount":250}]');
 update private.hub_stena_files_v1 set complete=true where tenant_id=t and file_hash=s;
 r:=public.hub_payment_outcome_source_v1(t,'2026-11-02');
 assert (select count(*) from jsonb_array_elements(r->'rows')x where x->>'reference'='99999887')=1,'Duplicate canonical booking';
 assert exists(select 1 from jsonb_array_elements(r->'rows')x where x->>'reference'='99999887' and x->>'amountStatus'='settled' and (x->>'amount')::numeric=250),'Settlement must replace history';
 assert not exists(select 1 from jsonb_array_elements(r->'rows')x where x->>'id'='fixture-a'),'Workify counted twice';
 assert exists(select 1 from jsonb_array_elements(r->'rows')x where x->>'id'='fixture-b' and (x->>'amount')::numeric=600),'Unpriced fallback missing';
 assert exists(select 1 from jsonb_array_elements(r->'rows')x where x->>'id'='fixture-other'),'Other customer was replaced';
 assert (r#>>'{controls,stena,replacedWorkifyRows}')::integer=1,'Replacement audit incorrect';
 -- A combined Workify row with one unpriced journey must retain its whole component.
 insert into payment_stena_fixture(fact_id,occurred_on,kind,amount,source,original,cost_center)
 values('fixture-combined','2026-10-01','revenue',1000,'Workify','{"Kundnamn":"Stena Recycling AB","Littranummer":"99999887 99999888"}','30');
 r:=public.hub_payment_outcome_source_v1(t,'2026-11-02');
 assert not exists(select 1 from jsonb_array_elements(r->'rows')x where x->>'source'='Stena portal' and x->>'reference'='99999887'),'Blocked component partially replaced';
 assert exists(select 1 from jsonb_array_elements(r->'rows')x where x->>'id'='fixture-combined'),'Combined fallback removed';
end $test$;
select 'PASS: history to settlement, canonical deduplication, exact customer matching, unpriced fallback and connected blocking' result;
rollback;
