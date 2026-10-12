-- Pure Hub reconciliation tests: no business-table mutations.
do $test$
declare base jsonb:='{"source_key":"a","row_id":"a1","amount":100,"quantity":null,"source_center":"30","receiver_center":"10","ready":false,"status":"review","occurred_on":"2026-09-01","order":"=source text","littra":"test","invoiced":false}'::jsonb;
 rows jsonb; r jsonb;
begin
 rows:=jsonb_build_array(base,base||'{"row_id":"a2","quantity":2}',
 base||'{"source_key":"credit","row_id":"b","amount":-10,"source_center":"20","ready":true,"status":"posted"}',
 base||'{"source_key":"unassigned","row_id":"c","amount":50,"source_center":null}',
 base||'{"source_key":"other","row_id":"d","amount":7,"receiver_center":"30","source_center":"20"}',
 base||'{"source_key":"changed","row_id":"e1","amount":100}',base||'{"source_key":"changed","row_id":"e2","amount":120}',
 base||'{"source_key":"quantity","row_id":"f1","amount":5,"quantity":1}',base||'{"source_key":"quantity","row_id":"f2","amount":5,"quantity":2}',
 base||'{"source_key":"same-real-load:1","row_id":"g1","amount":20}',base||'{"source_key":"same-real-load:2","row_id":"g2","amount":20}');
 r:=private.hub_internal_center_summary_engine_v2(rows);
 if (r->>'total')::numeric<>130 or (r->>'preliminaryTotal')::numeric<>140 or (r->>'confirmedTotal')::numeric<>-10 then raise exception 'Period/review/credit totals incorrect: %',r;end if;
 if (r->>'duplicateRowsRemoved')::int<>1 or (r->>'duplicateAmountRemoved')::numeric<>100 then raise exception 'Import copy was not counted exactly once';end if;
 if (r->>'conflictCount')::int<>2 or (r->>'conflictRawAmount')::numeric<>230 then raise exception 'Edited amount/quantity was silently selected';end if;
 if (r->>'unassignedAmount')::numeric<>50 or (r->>'otherAmount')::numeric<>7 or (r->>'sourceAmount')::numeric<>517 or not(r->>'reconciles')::boolean then raise exception 'Original amount is not completely explained';end if;
 if jsonb_array_length(r#>'{transfers,0,rows}')<>3 then raise exception 'Separate legitimate identical loads were collapsed';end if;
 if (private.hub_internal_center_summary_engine_v2('[]')->>'total')::numeric<>0 then raise exception 'Empty period incorrect';end if;
 if has_function_privilege('anon','public.hub_kpi_internal_center_summary_v2(uuid,date,date,integer[])','execute') then raise exception 'Anonymous report allowed';end if;
end $test$;
select 'PASS full reconciliation, copy removal, legitimate repeated loads, amount/quantity conflicts, credits, unassigned and empty periods' as test;
