-- Live approved import classification exceeds the former 45-second RPC limit.
ALTER FUNCTION public.hub_payment_outcome_source_v1(uuid,date) SET statement_timeout='120s';
NOTIFY pgrst, 'reload schema';
