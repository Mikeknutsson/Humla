import { parseImportFile } from "@/lib/kpi/parser";
import { DATA_KINDS, detectDataKind, suggestMapping, type DataKind } from "@/lib/kpi/schema";
import { createClient } from "@/lib/supabase/server";

export const runtime = "nodejs";

export async function POST(request: Request) {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return Response.json({ error: "Inloggning krävs." }, { status: 401 });

  try {
    const formData = await request.formData();
    const file = formData.get("file");
    const requestedKind = String(formData.get("dataKind") ?? "auto");
    if (!(file instanceof File)) return Response.json({ error: "Ingen fil valdes." }, { status: 400 });
    if (requestedKind !== "auto" && !Object.hasOwn(DATA_KINDS, requestedKind)) return Response.json({ error: "Ogiltig datatyp." }, { status: 400 });
    const table = await parseImportFile(file);
    const kind = requestedKind === "auto" ? detectDataKind(table.headers) : requestedKind as DataKind;
    return Response.json({
      file: { name: file.name, size: file.size, type: file.type },
      headers: table.headers,
      rows: table.rows.slice(0, 12),
      totalRows: table.rows.length,
      sheetName: table.sheetName,
      pageCount: table.pageCount,
      detectedKind: kind,
      suggestedMapping: kind ? suggestMapping(table.headers, kind) : {},
    });
  } catch (error) {
    return Response.json({ error: error instanceof Error ? error.message : "Filen kunde inte läsas." }, { status: 422 });
  }
}
