-- Add a read-only personnel reconciliation to the existing, scoped report.
-- Financial facts and payroll/overhead allocation rules remain authoritative.
do $migration$
declare definition text;
begin
 definition:=pg_get_functiondef('private.hub_kpi_management_accounting_basis_v1(uuid,integer,integer[],jsonb,jsonb)'::regprocedure);
 if strpos(definition,'declare timing jsonb;')=0 or strpos(definition,'into sources,fact_cost,next_cost,unassigned_cost;')=0 then
  raise exception 'Unexpected management accounting report definition';
 end if;
 definition:=replace(definition,'declare timing jsonb;','declare personnel jsonb;timing jsonb;');
 definition:=replace(definition,
  '(select sum(amount)from f where kind=''cost''and unit_id is null)',
  $new$(select sum(amount)from f where kind='cost'and unit_id is null),
 (select case when count(*)filter(where kind='cost')=0 then '{}'::jsonb else jsonb_build_object(
 'calculated_cost',round(coalesce(sum(amount)filter(where kind='cost'and category='personnel'),0),2),
 'transpa_estimate',round(coalesce(sum(amount)filter(where kind='cost'and category='personnel'and source='TransPA'),0),2),
 'next_personnel_cost',round(coalesce(sum(amount)filter(where kind='cost'and category='personnel'and source='NEXT'),0),2),
 'provisional_work_cost',round(coalesce(sum(amount)filter(where kind='cost'and category='personnel'and source='Preliminär arbetskostnad'),0),2),
 'other_personnel_cost',round(coalesce(sum(amount)filter(where kind='cost'and category='personnel'and coalesce(source,'')not in('TransPA','NEXT','Preliminär arbetskostnad')),0),2),
 'overhead_allocation',round(coalesce(sum(amount)filter(where kind='cost'and category='overhead'and source='Overhead'),0),2),
 'management_allocation',round(coalesce(sum(amount)filter(where kind='cost'and category='management'and source='Overhead'),0),2),
 'next_management_cost',round(coalesce(sum(amount)filter(where kind='cost'and category='management'and source='NEXT'),0),2)
 )end from f)$new$);
 definition:=replace(definition,'into sources,fact_cost,next_cost,unassigned_cost;','into sources,fact_cost,next_cost,unassigned_cost,personnel;');
 definition:=replace(definition,'return jsonb_build_object(''stena_timing'',timing,',
 $new$personnel:=personnel||jsonb_build_object(
 'booked_cost',-(ref.source#>>'{metrics,personnel,value}')::numeric,
 'cost_difference',round((personnel->>'calculated_cost')::numeric+(ref.source#>>'{metrics,personnel,value}')::numeric,2),
 'result_effect',round(-(ref.source#>>'{metrics,personnel,value}')::numeric-(personnel->>'calculated_cost')::numeric,2),
 'basis','Humlas personalkostnad kombinerar TransPA-schablon för lön och PO, importerad NEXT-personal och preliminär arbetskostnad. Bokförd personal hämtas från uppladdat ekonomiunderlag för exakt samma period och urval. Overhead och arbetsledning redovisas separat och ingår redan i rapportens totalkostnad; de ska inte läggas till personalkostnaden igen. Samma personalomfattning och löneperiod behöver verifieras. En positiv resultateffekt betyder att Humlas lägre personalkostnad höjer resultatet jämfört med bokföringsrapporten.'
 );
 return jsonb_build_object('personnel_comparison',personnel,'stena_timing',timing,$new$);
 if strpos(definition,'''personnel_comparison'',personnel')=0 then raise exception 'Personnel report extension failed';end if;
 execute definition;
end $migration$;
