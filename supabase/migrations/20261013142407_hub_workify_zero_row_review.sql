-- Match the existing import rule: zero-amount rows are ignored even without a date.
do $migration$
declare definition text; needle text; replacement text;
begin
 definition:=pg_get_functiondef('private.hub_workify_review_rows_v1(uuid)'::regprocedure);
 needle:=$old$when amount is null or amount::text in ('NaN','Infinity','-Infinity') or occurred_on is null then 'invalid'
   when amount=0 then 'ignored_zero'$old$;
 replacement:=$new$when amount=0 then 'ignored_zero'
   when amount is null or amount::text in ('NaN','Infinity','-Infinity') or occurred_on is null then 'invalid'$new$;
 if strpos(definition,needle)=0 then raise exception 'Unexpected Workify review definition';end if;
 execute replace(definition,needle,replacement);
end $migration$;
notify pgrst,'reload schema';
