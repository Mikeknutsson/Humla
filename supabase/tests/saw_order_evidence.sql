-- Read-only regression for shared-project evidence: generic terms and unknown orders must not allocate.
do $$declare t uuid;g uuid;o text;begin
 select r.tenant_id,s.active_generation into strict t,g from private.hub_saw_activity_rules_v1 r join private.hub_kpi_report_state s using(tenant_id);
 select original->>'Ordernummer' into o from private.hub_kpi_prepared_facts where tenant_id=t and generation_id=g and source='Workify' and original->>'Artikelnummer'='12-04' limit 1;
 if private.hub_saw_cost_evidence_v1(t,g,jsonb_build_object('Kommentar','Arbetsorder '||o)) is null then raise exception 'Known saw order not matched';end if;
 if private.hub_saw_cost_evidence_v1(t,g,'{"Kommentar":"Sågning av träd"}') is not null then raise exception 'Generic keyword accepted';end if;
 if private.hub_saw_cost_evidence_v1(t,g,'{"Kommentar":"AO 999999999"}') is not null then raise exception 'Unknown order accepted';end if;
 if private.hub_saw_cost_evidence_v1(t,g,'{"Kommentar":"Extra såggubbe 8 timmar"}') is null then raise exception 'Explicit operator evidence not matched';end if;
 if private.hub_saw_cost_evidence_v1(t,g,'{"Kommentar":"Ej extra såggubbe"}') is not null then raise exception 'Negated operator accepted';end if;
end $$;
