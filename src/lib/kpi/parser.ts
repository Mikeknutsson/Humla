import "server-only";
import * as XLSX from "xlsx";
import type { DataKind, ParsedRow, ParsedTable } from "./schema";
import { DATA_KINDS } from "./schema";
import { parseVehicleRules, resolveVehicle } from "./vehicle-rules";

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
  const workify = ['Ordernummer', 'Artikelnummer', 'Artikeldatum', 'Summa', 'Fakturerad'].every(h => headers.includes(h));
  // Workify emits attachment-only continuation rows; these are not transactions.
  const dataRows = nonEmpty.slice(1).filter(values => !workify || values.some((value, i) => String(value ?? '').trim() && !['Platser', 'FilUrl'].includes(headers[i])));
  if (dataRows.length > MAX_ROWS) throw new Error("Filen innehåller fler än 20 000 rader. Dela upp filen; inga rader har importerats.");
  const rows = dataRows.map((values) => Object.fromEntries(headers.map((header, index) => [header, String(values[index] ?? "").trim()])));
  return { headers, rows, sheetName };
}

function parsePdfLine(line: string): ParsedRow {
  const date = line.match(/\b(?:20\d{2}[-/.]\d{1,2}[-/.]\d{1,2}|\d{1,2}[-/.]\d{1,2}[-/.](?:20)?\d{2})\b/)?.[0] ?? "";
  const registration = line.toUpperCase().match(/\b[A-ZÅÄÖ]{3}\s?\d{2}[A-Z0-9]\b/)?.[0]?.replace(/\s/g, "") ?? "";
  const amountText = line.replace(date, "").replace(/\b[A-ZÅÄÖ]{3}\s?\d{2}[A-Z0-9]\b/gi, "");
  const numberTokens = [...amountText.matchAll(/-?\(?\d[\d\s.]*[,.]\d{1,2}\)?/g)].map((match) => match[0].trim());
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
  await import("pdf-parse/worker");
  const { PDFParse } = await import("pdf-parse");
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
  if (file.size > 4 * 1024 * 1024) throw new Error("Filen är större än 4 MB. Dela upp den före import.");
  const extension = file.name.split(".").pop()?.toLowerCase();
  const buffer = new Uint8Array(await file.arrayBuffer());
  if (extension === "pdf" || file.type === "application/pdf") return parsePdf(buffer);
  if (["xlsx", "xls", "csv"].includes(extension ?? "")) return parseWorkbook(buffer);
  throw new Error("Filtypen stöds inte. Använd PDF, XLSX, XLS eller CSV.");
}

function numberValue(value: string | undefined) {
  if (!value?.trim()) return null;
  let text = value.trim().replace(/[A-Za-zÅÄÖåäö€$£]/g, "").replace(/\s/g, "");
  if (!/\d/.test(text)) return null;
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
  const rules = parseVehicleRules(mapping.__vehicle_rules ?? "", table.headers);
  const field = (row: ParsedRow, key: string) => mapping[key] ? row[mapping[key]]?.trim() ?? "" : "";
  const required = DATA_KINDS[kind].fields.filter((item) => item.required).map((item) => item.key);
  return table.rows.map((source, index) => {
    const occurredOn = dateValue(field(source, "occurred_on"));
    const vehicle = resolveVehicle(source, field(source, "vehicle_registration"), rules);
    const row = {
      row_number: index + 1,
      data_kind: kind,
      occurred_on: occurredOn,
      vehicle_registration: vehicle.registration,
      employee_number: field(source, "employee_number") || null,
      project_reference: field(source, "project_reference") || null,
      cost_center: field(source, "cost_center") || null,
      account: field(source, "account") || null,
      description: (kind === "next_historical_time" ? field(source, "time_role") : field(source, "description")) || null,
      quantity: numberValue(field(source, "quantity")),
      amount: numberValue(field(source, "amount")),
      available_hours: numberValue(field(source, "available_hours")),
      occupied_hours: numberValue(field(source, "occupied_hours")),
      paid_hours: numberValue(field(source, "paid_hours")),
      billable_hours: numberValue(field(source, "billable_hours")),
      source_data: source,
    };
    const errors: string[] = [];
    if (vehicle.error) errors.push(vehicle.error);
    for (const key of required) {
      const value = row[key as keyof typeof row];
      if (value === null || value === "") errors.push(`${key} saknas eller är ogiltigt`);
    }
    for (const key of ['available_hours', 'occupied_hours', 'paid_hours', 'billable_hours'] as const) {
      if (row[key] !== null && row[key]! < 0) { errors.push(`${key} får inte vara negativt`); row[key] = null; }
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
