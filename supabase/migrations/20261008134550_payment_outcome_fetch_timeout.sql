-- Keep the extended budget scoped to the payment source RPC; all other API limits remain unchanged.
alter function public.hub_payment_outcome_source_v1(uuid,date) set statement_timeout='45s';
notify pgrst, 'reload schema';
