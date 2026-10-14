import { allocateWorkify, isWorkify } from "@/lib/kpi/workify";
import { canonicalExternalIdentity, resolveHubMapping } from "@/lib/hub/import-reuse-contract.mjs";
import { createHash, randomUUID } from "node:crypto";
import { parseImportFile, normalizeRows, mimeForFile } from "@/lib/kpi/parser";
import { DATA_KINDS, type DataKind } from "@/lib/kpi/schema";
import { createClient } from "@/lib/supabase/server";

export const runtime = "nodejs";
export const maxDuration = 120;

function normalizeProjectReference(value: string | null | undefined) {
  return String(value ?? "").normalize("NFKC").trim().toUpperCase().replace(/^(?:PROJEKT(?:NR|NUMMER)?|PROJECT|NR)\s*[:#-]?\s*/i, "").replace(/\s+/g, "").replace(/\.0+$/, "");
}

function safeName(value: string) {
  return value.normalize("NFKD").replace(/[^a-zA-Z0-9._-]/g, "_").slice(-120);
}

export async function POST(request: Request) {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return Response.json({ error: "Inloggning krävs." }, { status: 401 });

  const { data: member } = await supabase.from("hub_tenant_members").select("tenant_id").eq("user_id", user.id).eq("status", "active").maybeSingle();
  if (!member) return Response.json({ error: "Aktivt företag saknas." }, { status: 403 });
  const { data: allowed } = await supabase.rpc("hub_has_permission", { p_tenant_id: member.tenant_id, p_permission: "kpi.manage" });
  if (!allowed) return Response.json({ error: "Behörigheten kpi.manage krävs." }, { status: 403 });

  let batchId: string | null = null;
  try {
    const formData = await request.formData();
    const file = formData.get("file");
    const kind = String(formData.get("dataKind") ?? "") as DataKind;
    if (!(file instanceof File)) return Response.json({ error: "Ingen fil valdes." }, { status: 400 });
    if (!Object.hasOwn(DATA_KINDS, kind)) return Response.json({ error: "Ogiltig datatyp." }, { status: 400 });
    const mapping = JSON.parse(String(formData.get("mapping") ?? "{}")) as Record<string, string>;
    if (!mapping || Array.isArray(mapping) || typeof mapping !== "object" || Object.values(mapping).some((value) => typeof value !== "string")) return Response.json({ error: "Ogiltig kolumnmappning." }, { status: 400 });
    for (const definition of DATA_KINDS[kind].fields.filter((field) => field.required)) {
      if (!mapping[definition.key]) return Response.json({ error: `Mappa det obligatoriska fältet ${definition.label}.` }, { status: 400 });
    }

    const bytes = new Uint8Array(await file.arrayBuffer());
    const fileHash = createHash("sha256").update(bytes).digest("hex");
    const table = await parseImportFile(new File([bytes], file.name, { type: file.type }));
    let normalized = normalizeRows(table, kind, mapping);
    // NEXT costs and historical hours are separate measures. Never derive
    // a second wage cost from imported hours or count cost-file hours as time.
    if (kind === "next_historical_time") {
      normalized = normalized.map((row) => ({ ...row, amount: null }));
    } else if (kind === "cost") {
      normalized = normalized.map((row) => ({ ...row, paid_hours: null, billable_hours: null }));
    }
    if (kind === 'revenue' && isWorkify(table)) {
      const { data: rules, error } = await supabase.from('kpi_workify_article_rules').select('id,article_number,project_reference,cost_center,source_hash,revenue_category').eq('tenant_id', member.tenant_id).eq('enabled', true);
      if (error) throw new Error('Artikelregistret kunde inte läsas. Försök igen.');
      // Confirmed Workify labels resolve through Hub, never through a guessed
      // registration or a new parallel identity registry.
      const labelFor = (row: typeof normalized[number]) => String(row.source_data[mapping.vehicle_registration] ?? row.source_data.RegNr ?? row.vehicle_registration ?? '').trim().toUpperCase();
      const labels = [...new Set(normalized.map(labelFor).filter(Boolean))];
      if (labels.length) {
        const { data: aliases, error: aliasError } = await supabase.from('hub_identity_keys')
          .select('identity_value,object_id').eq('tenant_id', member.tenant_id)
          .eq('object_type', 'Vehicle').eq('identity_type', 'workify_vehicle_label')
          .eq('confidence', 1).in('identity_value', labels);
        if (aliasError) throw new Error('Hubbens bekräftade fordonsbenämningar kunde inte läsas.');
        const candidates = new Map<string, Array<{ id: string; humlaObjectId: string; confirmed: boolean; validFrom: string }>>();
        for (const alias of aliases ?? []) {
          const label = alias.identity_value.trim().toUpperCase();
          // External labels are scoped by tenant and adapter; they are never a Humla ID.
          canonicalExternalIdentity({ tenantId: member.tenant_id, source: "workify", entityType: "vehicle", externalId: label });
          const rules = candidates.get(label) ?? [];
          rules.push({ id: label, humlaObjectId: alias.object_id, confirmed: true, validFrom: "0001-01-01" });
          candidates.set(label, rules);
        }
        normalized = normalized.map(row => {
          const label = labelFor(row);
          // Historical validity isn't available in hub_identity_keys yet. The
          // fallback start date preserves existing confirmed-label behaviour;
          // the full effective-dated allocation engine runs in Hub's RPC.
          if (!label || !row.occurred_on) return row;
          const match = resolveHubMapping({ candidates: candidates.get(label) ?? [], effectiveDate: row.occurred_on });
          if (match.status !== "resolved") return row;
          const errors = row.validation_errors.filter(error => error !== 'Fordonsbeteckning saknar verifierad regnummerkoppling');
          return { ...row, vehicle_object_id: match.humlaObjectId, vehicle_registration: label,
            validation_errors: errors, is_valid: errors.length === 0 };
        });
      }
      normalized = allocateWorkify(normalized, rules ?? []);
    }
    // Match source project numbers regardless of harmless Excel/text formatting.
    // Never infer a vehicle from a partial or approximate project number.
    const projectRefs = [...new Set(normalized.map((row) => normalizeProjectReference(row.project_reference)).filter(Boolean))];
    if (projectRefs.length && kind !== "cost") {
      const { data: projectMappings, error: projectMappingError } = await supabase
        .from("kpi_project_unit_mappings")
        .select("project_reference,vehicle_registration")
        .eq("tenant_id", member.tenant_id)
        .eq("enabled", true);
      if (projectMappingError) throw new Error("Projekt-/fordonsregistret kunde inte läsas.");
      const vehicleByProject = new Map<string, string>();
      const conflicts = new Set<string>();
      for (const item of projectMappings ?? []) {
        if (!item.vehicle_registration) continue;
        const key = normalizeProjectReference(item.project_reference);
        const registration = String(item.vehicle_registration).toUpperCase().replace(/[\s-]/g, "");
        if (vehicleByProject.has(key) && vehicleByProject.get(key) !== registration) conflicts.add(key);
        else vehicleByProject.set(key, registration);
      }
      for (const key of conflicts) vehicleByProject.delete(key);
      normalized = normalized.map((row) => {
        const registration = row.vehicle_registration || (row.project_reference ? vehicleByProject.get(normalizeProjectReference(row.project_reference)) : null);
        if (!registration) return row;
        // A verified exact project mapping resolves the otherwise misleading
        // descriptive vehicle-text error in NEXT exports.
        const errors = row.validation_errors.filter((error) => error !== "Fordonsbeteckning saknar verifierad regnummerkoppling");
        return { ...row, vehicle_registration: registration, validation_errors: errors, is_valid: errors.length === 0 };
      });
    }
    // A NEXT project reference is not evidence of a vehicle allocation.
    // Keep unassigned cost rows in review until explicitly classified.
    if (kind === "cost") normalized = normalized.map((row) => {
      const errors = row.validation_errors.filter((error) => error !== "Fordonsbeteckning saknar verifierad regnummerkoppling");
      const verifiedVehicle = row.vehicle_registration && /^[A-Z]{3}[0-9]{2}[A-Z0-9]$/.test(row.vehicle_registration);
      return { ...row, vehicle_registration: verifiedVehicle ? row.vehicle_registration : null,
        validation_errors: verifiedVehicle ? errors : [...errors, "Kostnadsfördelning behöver granskas"],
        is_valid: Boolean(verifiedVehicle) && errors.length === 0,
        allocation: { allocation_status: verifiedVehicle ? "vehicle_direct" : "unallocated_review",
          allocation_type: verifiedVehicle ? "vehicle" : null } };
    });
    // NEXT cost exports frequently map "Verifikationstext" to the vehicle field.
    // That is a description, not a registration. Unmapped rows stay in review,
    // while verified project mappings above release their corresponding rows.
    let validRows = normalized.filter((row) => row.is_valid);
    const dates = validRows.map((row) => row.occurred_on).filter((value): value is string => Boolean(value)).sort();
    batchId = randomUUID();
    const path = `${member.tenant_id}/${batchId}/${safeName(file.name)}`;
    const sourceType = file.name.toLowerCase().endsWith(".pdf") ? "manual_pdf" : "manual_excel";

    const { error: batchError } = await supabase.from("kpi_import_batches").insert({
      id: batchId,
      tenant_id: member.tenant_id,
      source_type: sourceType,
      data_kind: kind,
      file_name: file.name,
      file_type: mimeForFile(file),
      file_size: file.size,
      file_hash: fileHash,
      storage_path: path,
      status: "processing",
      row_count: normalized.length,
      valid_row_count: validRows.length,
      invalid_row_count: normalized.length - validRows.length,
      period_start: dates.at(0) ?? null,
      period_end: dates.at(-1) ?? null,
      column_mapping: mapping,
      provenance: { channel: "manual_upload", original_preserved: true, parser: "humla-kpi/1.0", hub_import_contract: "core-001/v1", hub_ingestion: kind === "cost" ? "hub_kpi_ingest_cost_file_v1" : (kind === "revenue" && isWorkify(table)) ? "hub_kpi_ingest_workify_file_v1" : "legacy_import", canonical_mapping: "hub_identity_keys", source_file_sha256: fileHash },
      created_by: user.id,
    });
    if (batchError?.code === "23505") {
      if(kind==='revenue'&&isWorkify(table)){
        const {data:previous}=await supabase.from('kpi_import_batches').select('id,status,provenance').eq('tenant_id',member.tenant_id).eq('data_kind',kind).eq('file_hash',fileHash).maybeSingle();
        if(previous&&['completed','needs_review'].includes(previous.status)&&previous.provenance?.workify_import_result?.status!=='blocked_changes'){
          const ignoredZeroRows=normalized.filter(r=>r.amount===0).length;
          return Response.json({batchId:previous.id,status:previous.status,rows:0,insertedRows:0,duplicateRowsSkipped:normalized.length-ignoredZeroRows,ignoredZeroRows,validRows:0,invalidRows:0},{status:200});
        }
      }
      return Response.json({error:'Samma fil finns redan. Kontrollera den tidigare importens status i Senaste importer; inga nya rader har lagts till.'},{status:409});
    }
    if (batchError) throw batchError;

    const { error: uploadError } = await supabase.storage.from("kpi-imports").upload(path, bytes, { contentType: mimeForFile(file), upsert: false });
    if (uploadError) throw new Error(`Originalfilen kunde inte sparas: ${uploadError.message}`);

    if (kind === 'revenue' && isWorkify(table)) {
      // One atomic Hub transaction protects overlapping full-year imports,
      // legitimate repeated source lines and simultaneous uploads.
      const {data:ingested,error:ingestError}=await supabase.rpc('hub_kpi_ingest_workify_file_v1', {
        p_tenant_id:member.tenant_id,p_batch_id:batchId,p_rows:normalized,
      });
      if(ingestError)throw ingestError;
      if(ingested.status==='blocked_changes')return Response.json({
        ...ingested,batchId,error:`Importen stoppades: ${ingested.changedRows} rader på befintliga ordrar har ändrats eller kan inte skiljas säkert från tidigare rader. Originalfilen är sparad. Inga nya ekonomirader har lagts till och inga tidigare belopp har skrivits över.`,
      },{status:409});
      const resolved=ingested.insertedRows>0?await supabase.rpc('hub_kpi_resolve_workify_import_v1',{
        p_tenant_id:member.tenant_id,p_batch_id:batchId,
      }):{data:{},error:null};
      if(resolved.error)throw resolved.error;
      return Response.json({batchId,rows:ingested.insertedRows,...ingested,...resolved.data},{status:201});
    }

    if (kind === 'cost') {
      // Dashboard is only an upload client. Hub owns identity, deduplication and storage.
      // The original file has already been persisted in the tenant-scoped Hub bucket.
      const {data:ingested,error:ingestError}=await supabase.rpc('hub_kpi_ingest_cost_file_v1',{
        p_tenant_id:member.tenant_id,p_batch_id:batchId,p_rows:normalized,
      });
      if(ingestError)throw ingestError;
      return Response.json({batchId,rows:ingested.insertedRows,...ingested},{status:201});
    }

    for (let offset = 0; offset < normalized.length; offset += 500) {
      const payload = normalized.slice(offset, offset + 500).map((row) => ({ ...row, tenant_id: member.tenant_id, batch_id: batchId, currency: "SEK" }));
      async function saveRows(items: typeof payload): Promise<void> {
        const { error } = await supabase.from("kpi_import_rows").insert(items);
        if (!error) return;
        // Only row-data errors are isolated. Auth, storage and service failures remain fatal.
        if (!(error.code.startsWith('22') || error.code === '23514')) throw error;
        if (items.length > 1) {
          const mid = Math.floor(items.length / 2);
          await saveRows(items.slice(0, mid)); await saveRows(items.slice(mid)); return;
        }
        const item = items[0];
        const held = { ...item, occurred_on: null, amount: null, quantity: null, available_hours: null, occupied_hours: null, paid_hours: null, billable_hours: null,
          is_valid: false, validation_errors: [...item.validation_errors, `Datavärde behöver granskas (${error.code})`] };
        const { error: holdError } = await supabase.from('kpi_import_rows').insert(held);
        if (holdError) throw holdError;
        normalized[item.row_number - 1] = held;
      }
      await saveRows(payload);
    }

    validRows = normalized.filter(row => row.is_valid);
    const status = validRows.length === normalized.length ? "completed" : "needs_review";
    const { error: updateError } = await supabase.from("kpi_import_batches").update({
      status,
      valid_row_count: validRows.length,
      invalid_row_count: normalized.length - validRows.length,
      completed_at: new Date().toISOString(),
      error_summary: normalized.filter((row) => !row.is_valid).slice(0, 50).map((row) => ({ row: row.row_number, errors: row.validation_errors })),
    }).eq("id", batchId);
    if (updateError) throw updateError;

    return Response.json({ batchId, status, rows: normalized.length, validRows: validRows.length, invalidRows: normalized.length - validRows.length }, { status: 201 });
  } catch (error) {
    if (batchId) await supabase.from("kpi_import_batches").update({ status: "failed", error_summary: [{ message: error instanceof Error ? error.message : "Importen misslyckades" }] }).eq("id", batchId);
    return Response.json({ error: error instanceof Error ? error.message : "Importen misslyckades." }, { status: 500 });
  }
}
