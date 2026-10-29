begin;set local jit=off;select set_config('request.jwt.claim.sub','5a6fa4c4-5427-47fa-9835-d997fe81c7d5',true);
do $test$
declare t uuid:='944597b6-9c46-4bef-998d-f19e23c4245b';g uuid;r jsonb;n integer;
begin
 select active_generation into g from private.hub_kpi_report_state where tenant_id=t;
 r:=private.hub_detach_vehicle_nontransport_v1(t,g);
 assert (r->>'changed_rows')::int=0,'Second run must be idempotent';
 select count(*) into n from private.hub_kpi_prepared_facts f join public.hub_objects o on o.id=f.unit_id and o.object_type='EconomicUnit'
 where f.tenant_id=t and f.generation_id=g and f.source='Workify' and f.kind='revenue' and f.occurred_on>='2025-09-01' and o.data->>'unit_type' in('vehicle','compound')
 and ((f.original->>'Artikelnummer'='3-29' and coalesce(f.original->>'Artikelnamn',f.description) ilike 'Tippavgift IFA-Schakt%')
 or(coalesce(f.original->>'Artikelnamn',f.description) ~* '^(Krossmaterial|Murgrus|Rörgrus|Gjutgrus|Natursingel)' and concat_ws(' ',f.original->>'Artikelnamn',f.description) !~* 'transport|uttaget.*kund'));
 assert n=0,'Eligible non-transport sales remain on vehicles';
 select count(*) into n from private.hub_kpi_prepared_facts f left join private.hub_kpi_prepared_display_facts d on d.tenant_id=f.tenant_id and d.generation_id=f.generation_id and d.fact_id=f.fact_id
 where f.tenant_id=t and f.generation_id=g and f.original?'_humla_vehicle_component_correction' and(d.fact_id is null or row(f.amount,f.unit_id,f.project,f.vehicle,f.category,f.business_group) is distinct from row(d.amount,d.unit_id,d.project,d.vehicle,d.category,d.business_group));
 assert n=0,'Display mismatch';
end $test$;
select 'PASS: idempotence, no eligible material/IFA revenue on vehicles, display synchronization, built-in financial conservation' verification;
rollback;