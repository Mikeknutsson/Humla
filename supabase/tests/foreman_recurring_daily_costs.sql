-- Run with the SQL implementation in the same rollback transaction.
do $test$
declare f private.hub_kpi_prepared_display_facts;n numeric;cnt integer;
begin
 f.fact_id:='test-depreciation';f.kind:='cost';f.source:='Avskrivningsregister';f.category:='depreciation';f.occurred_on:='2026-11-01';f.amount:=3000;f.original:='{}';
 select sum(amount),count(*) into n,cnt from private.hub_foreman_recurring_fact_v1(f,'{}','2026-11-01','2026-11-15');
 assert n=1500 and cnt=15,'Partial month must stop at selected date';
 select sum(amount)into n from private.hub_foreman_recurring_fact_v1(f,'{}','2026-11-16','2026-11-30');assert n=1500,'Midmonth start lost recurring costs';
 select sum(amount)into n from private.hub_foreman_recurring_fact_v1(f,'{"valid_from":"2026-11-10","valid_to":"2026-11-20"}','2026-11-01','2026-11-30');assert n=1100,'Validity bounds ignored';
 f.occurred_on:='2024-02-01';f.amount:=2900;
 select sum(amount)into n from private.hub_foreman_recurring_fact_v1(f,'{}','2024-02-01','2024-02-14');assert n=1400,'Leap year denominator wrong';
 f.occurred_on:='2026-10-01';f.amount:=100;
 select sum(amount)into n from private.hub_foreman_recurring_fact_v1(f,'{}','2026-10-01','2026-10-31');assert n=100,'Full month cents changed';
 f.amount:=-100;select sum(amount)into n from private.hub_foreman_recurring_fact_v1(f,'{}','2026-10-01','2026-10-31');assert n=-100,'Credit changed';
 f.source:='Preliminär arbetskostnad';f.occurred_on:='2026-09-30';f.amount:=3000;
 select sum(amount)into n from private.hub_foreman_recurring_fact_v1(f,'{"_humla_provisional_cost":{"month":"2026-09-01"}}','2026-09-01','2026-09-15');assert n=1500,'Monthly estimate must accrue before posting date';
 f.source:='Overhead';f.occurred_on:='2026-09-08';f.amount:=123.45;
 select sum(amount),count(*)into n,cnt from private.hub_foreman_recurring_fact_v1(f,'{"_humla_monthly_overhead":{"monthly_amount":3000}}','2026-09-01','2026-09-15');assert n=123.45 and cnt=1,'Daily overhead was prorated twice';
 f.source:='NEXT';f.amount:=987.65;
 select sum(amount),count(*)into n,cnt from private.hub_foreman_recurring_fact_v1(f,'{}','2026-09-01','2026-09-15');assert n=987.65 and cnt=1,'Booked source cost changed';
 select sum(amount),count(*)into n,cnt from private.hub_foreman_recurring_fact_v1(f,'{"_humla_provisional_cost":{"month":"2026-09-01"}}','2026-09-01','2026-09-15');assert n=987.65 and cnt=1,'Actual NEXT source must not be treated as a monthly estimate';
 select count(*)into cnt from private.hub_foreman_recurring_fact_v1(f,'{}','2026-09-09','2026-09-15');assert cnt=0,'Cost outside selected period included';
end $test$;
select 'PASS: partial/full months, midmonth starts, register validity, leap year, credits, monthly estimate and unchanged daily/source costs' verification;

