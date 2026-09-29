import "server-only";
import * as XLSX from "xlsx";
import { PDFParse } from "pdf-parse";
import type { DataKind, ParsedRow, ParsedTable } from "./schema";
import { DATA_KINDS } from "./schema";

const MAX_ROWS = 20_000;

function uniqueHeaders(values: unknown[]) {
  const seen = new Map<string, number>();
  return values.map((value, index) => {
    const base = String(value ?? "").trim() || `Kolumn ${index + 1}`;
    const count = (seen.get(base) ?? 0) + 1;
    seen.set(base, count);
    return count === 1 ? base : `${base} (${count})`;
  });
}

function parseWorkbook(buffer: Uint8Array): ParsedTable {
  const workbook = XLSX.read(buffer, { type: "array", cellDates: false });
  const sheetName = workbook.SheetNames[0];
  if (!sheetName) throw new Error("Excel-filen innehåller inget kalkylblad.");
  const matrix = XLSX.utils.sheet_to_json<unknown[]>(workbook.Sheets[sheetName], { header: 1, defval: "", raw: false });
  const nonEmpty = matrix.filter((row) => row.some((cell) => String(cell ?? "").trim()));
  if (!nonEmpty.length) throw new Error("Filen innehåller inga datarader.");
  const headers = uniqueHeaders(nonEmpty[0]);
  const rows = nonEmpty.slice(1, MAX_ROWS + 1).map((values) => Object.fromEntries(headers.map((header, index) => [header, String(values[index] ?? "").trim()])));
  return { headers, rows, sheetName };
}

function parsePdfLine(line: string): ParsedRow {
  const date = line.match(/\b(?:20\d{2}[-/.]\d{1,2}[-/.]\d{1,2}|\d{1,2}[-/.]\d{1,2}[-/.](?:20)?\d{2})\b/)?.[0] ?? "";
  const registration = line.toUpperCase().match(/\b[A-ZÅÄÖ]{3}\s?\d{2}[A-Z0-9]\b/)?.[0]?.replace(/\s/g, "") ?? "";
  const numberTokens = [...line.matchAll(/-?\(?\d[\d\s.]*[,.]\d{1,2}\)?/g)].map((match) => match[0]);
  return {
    Radtext: line,
    Datum: date,
    Registreringsnummer: registration,
    Belopp: numberTokens.at(-1) ?? "",
    Antal: "",
    Timmar: "",
    Anställningsnummer: "",
  };
}

async function parsePdf(buffer: Uint8Array): Promise<ParsedTable> {
  const parser = new PDFParse({ data: buffer });
  try {
    const result = await parser.getText();
    const rows = result.text.split(/\r?\n/).map((line) => line.replace(/\s+/g, " ").trim()).filter((line) => line.length > 2).slice(0, MAX_ROWS).map(parsePdfLine);
    if (!rows.length) throw new Error("PDF-filen saknar maskinläsbar text. Skannade dokument behöver OCR innan import.");
    return { headers: ["Radtext", "Datum", "Registreringsnummer", "Belopp", "Antal", "Timmar", "Anställningsnummer"], rows, pageCount: result.total };
  } finally {
    await parser.destroy();
  }
}

export async function parseImportFile(file: File): Promise<ParsedTable> {
  if (file.size > 20 * 1024 * 1024) throw new Error("Filen är större än 20 MB.");
  const extension = file.name.split(".").pop()?.toLowerCase();
  const buffer = new Uint8Array(await file.arrayBuffer());
  if (extension === "pdf" || file.type === "application/pdf") return parsePdf(buffer);
  if (["xlsx", "xls", "csv"].includes(extension ?? "")) return parseWorkbook(buffer);
  throw new Error("Filtypen stöds inte. Använd PDF, XLSX, XLS eller CSV.");
}

function numberValue(value: string | undefined) {
  if (!value?.trim()) return null;
  let text = value.trim().replace(/[A-Za-zÅÄÖåäö€$£]/g, "").replace(/\s/g, "");
  const negative = /^\(.*\)$/.test(text);
  text = text.replace(/[()]/g, "");
  if (text.includes(",") && text.includes(".")) {
    text = text.lastIndexOf(",") > text.lastIndexOf(".") ? text.replace(/\./g, "").replace(",", ".") : text.replace(/,/g, "");
  } else if (text.includes(",")) text = text.replace(/\./g, "").replace(",", ".");
  const parsed = Number(text);
  return Number.isFinite(parsed) ? (negative ? -parsed : parsed) : null;
}

function dateValue(value: string | undefined) {
  if (!value?.trim()) return null;
  const text = value.trim();
  if (/^\d{5}(?:\.\d+)?$/.test(text)) {
    const parsed = XLSX.SSF.parse_date_code(Number(text));
    if (parsed) return `${parsed.y}-${String(parsed.m).padStart(2, "0")}-${String(parsed.d).padStart(2, "0")}`;
  }
  const parts = text.match(/^(\d{1,4})[-/.](\d{1,2})[-/.](\d{1,4})$/);
  if (!parts) return null;
  const yearFirst = parts[1].length === 4;
  const year = Number(yearFirst ? parts[1] : parts[3].length === 2 ? `20${parts[3]}` : parts[3]);
  const month = Number(parts[2]);
  const day = Number(yearFirst ? parts[3] : parts[1]);
  const date = new Date(Date.UTC(year, month - 1, day));
  if (date.getUTCFullYear() !== year || date.getUTCMonth() !== month - 1 || date.getUTCDate() !== day) return null;
  return `${year}-${String(month).padStart(2, "0")}-${String(day).padStart(2, "0")}`;
}

export function normalizeRows(table: ParsedTable, kind: DataKind, mapping: Record<string, string>) {
  const field = (row: ParsedRow, key: string) => mapping[key] ? row[mapping[key]]?.trim() ?? "" : "";
  const required = DATA_KINDS[kind].fields.filter((item) => item.required).map((item) => item.key);
  return table.rows.map((source, index) => {
    const occurredOn = dateValue(field(source, "occurred_on"));
    const row = {
      row_number: index + 1,
      data_kind: kind,
      occurred_on: occurredOn,
      vehicle_registration: field(source, "vehicle_registration").toUpperCase().replace(/[^A-Z0-9ÅÄÖ]/g, "") || null,
      employee_number: field(source, "employee_number") || null,
      project_reference: field(source, "project_reference") || null,
      cost_center: field(source, "cost_center") || null,
      account: field(source, "account") || null,
      description: field(source, "description") || null,
      quantity: numberValue(field(source, "quantity")),
      amount: numberValue(field(source, "amount")),
      available_hours: numberValue(field(source, "available_hours")),
      occupied_hours: numberValue(field(source, "occupied_hours")),
      paid_hours: numberValue(field(source, "paid_hours")),
      billable_hours: numberValue(field(source, "billable_hours")),
      source_data: source,
    };
    const errors: string[] = [];
    for (const key of required) {
      const value = row[key as keyof typeof row];
      if (value === null || value === "") errors.push(`${key} saknas eller är ogiltigt`);
    }
    if (row.occupied_hours !== null && row.available_hours !== null && row.occupied_hours > row.available_hours) errors.push("belagd tid överstiger tillgänglig tid");
    if (row.billable_hours !== null && row.paid_hours !== null && row.billable_hours > row.paid_hours) errors.push("debiterbar tid överstiger betald tid");
    return { ...row, is_valid: errors.length === 0, validation_errors: errors };
  });
}

export function mimeForFile(file: File) {
  const extension = file.name.split(".").pop()?.toLowerCase();
  if (extension === "pdf") return "application/pdf";
  if (extension === "xlsx") return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";
  if (extension === "xls") return "application/vnd.ms-excel";
  if (extension === "csv") return "text/csv";
  return file.type || "application/octet-stream";
}
