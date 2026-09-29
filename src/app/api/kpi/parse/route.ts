import { parseImportFile } from "@/lib/kpi/parser";
import { DATA_KINDS, suggestMapping, type DataKind } from "@/lib/kpi/schema";
import { createClient } from "@/lib/supabase/server";

export const runtime = "nodejs";

export async function POST(request: Request) {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return Response.json({ error: "Inloggning krävs." }, { status: 401 });

  try {
    const formData = await request.formData();
    const file = formData.get("file");
    const kind = String(formData.get("dataKind") ?? "") as DataKind;
    if (!(file instanceof File)) return Response.json({ error: "Ingen fil valdes." }, { status: 400 });
    if (!DATA_KINDS[kind]) return Response.json({ error: "Ogiltig datatyp." }, { status: 400 });
    const table = await parseImportFile(file);
    return Response.json({
      file: { name: file.name, size: file.size, type: file.type },
      headers: table.headers,
      rows: table.rows.slice(0, 12),
      totalRows: table.rows.length,
      sheetName: table.sheetName,
      pageCount: table.pageCount,
      suggestedMapping: suggestMapping(table.headers, kind),
    });
  } catch (error) {
    return Response.json({ error: error instanceof Error ? error.message : "Filen kunde inte läsas." }, { status: 422 });
  }
}
