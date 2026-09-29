import { allocateWorkify, isWorkify } from "@/lib/kpi/workify";
import { createHash, randomUUID } from "node:crypto";
import { parseImportFile, normalizeRows, mimeForFile } from "@/lib/kpi/parser";
import { DATA_KINDS, type DataKind } from "@/lib/kpi/schema";
import { createClient } from "@/lib/supabase/server";

export const runtime = "nodejs";

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
    if (kind === 'revenue' && isWorkify(table)) {
      const { data: rules, error } = await supabase.from('kpi_workify_article_rules').select('id,article_number,project_reference,cost_center,source_hash').eq('tenant_id', member.tenant_id).eq('enabled', true);
      if (error) throw new Error('Artikelregistret kunde inte läsas. Försök igen.');
      normalized = allocateWorkify(normalized, rules ?? []);
    }
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
      provenance: { channel: "manual_upload", original_preserved: true, parser: "humla-kpi/1.0" },
      created_by: user.id,
    });
    if (batchError?.code === "23505") return Response.json({ error: "Samma fil har redan importerats för denna datatyp." }, { status: 409 });
    if (batchError) throw batchError;

    const { error: uploadError } = await supabase.storage.from("kpi-imports").upload(path, bytes, { contentType: mimeForFile(file), upsert: false });
    if (uploadError) throw new Error(`Originalfilen kunde inte sparas: ${uploadError.message}`);

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
