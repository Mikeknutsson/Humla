do $patch$declare d text;begin
 d:=pg_get_functiondef('public.hub_kpi_save_accounting_reference_v1(uuid,date,date,text,jsonb,text)'::regprocedure);
 if position('correction_revision=correction_revision+1'in d)=0 then
  if position(' if rid is null then select id into rid'in d)=0 then raise exception 'Reference writer changed';end if;
  d:=replace(d,' if rid is null then select id into rid',' if rid is not null then update private.hub_kpi_report_state set correction_revision=correction_revision+1 where tenant_id=p_tenant_id;end if;
 if rid is null then select id into rid');
  execute d;
 end if;
end $patch$;
