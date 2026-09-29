export type DataKind =
  | "revenue"
  | "cost"
  | "fuel"
  | "vehicle_activity"
  | "driver_time";

export type ParsedRow = Record<string, string>;

export type ParsedTable = {
  headers: string[];
  rows: ParsedRow[];
  sheetName?: string;
  pageCount?: number;
};

export type FieldDefinition = {
  key: string;
  label: string;
  required?: boolean;
  aliases: string[];
};

const shared: FieldDefinition[] = [
  { key: "occurred_on", label: "Datum", required: true, aliases: ["datum", "date", "bokföringsdatum", "fakturadatum", "utförd datum", "period"] },
  { key: "vehicle_registration", label: "Registreringsnummer", aliases: ["regnr", "reg nr", "registreringsnummer", "fordon", "bil", "vehicle"] },
  { key: "project_reference", label: "Projekt/AO", aliases: ["projekt", "projektnummer", "ao", "arbetsorder", "order", "project"] },
  { key: "cost_center", label: "Kostnadsställe", aliases: ["kostnadsställe", "kst", "cost center", "costcenter"] },
  { key: "description", label: "Beskrivning", aliases: ["beskrivning", "text", "benämning", "artikel", "description", "radtext"] },
];

export const DATA_KINDS: Record<DataKind, { label: string; description: string; fields: FieldDefinition[] }> = {
  revenue: {
    label: "Omsättning",
    description: "Fakturor, orderintäkter eller utfört värde per fordon.",
    fields: [...shared, { key: "amount", label: "Intäktsbelopp", required: true, aliases: ["belopp", "summa", "netto", "intäkt", "omsättning", "amount"] }],
  },
  cost: {
    label: "Övriga kostnader",
    description: "Kostnader exklusive de dieselposter som importeras separat.",
    fields: [...shared, { key: "account", label: "Konto", aliases: ["konto", "kontonummer", "account"] }, { key: "amount", label: "Kostnadsbelopp", required: true, aliases: ["belopp", "summa", "kostnad", "amount"] }],
  },
  fuel: {
    label: "Diesel och bränsle",
    description: "Bränslekostnad och volym per tankning eller period.",
    fields: [...shared, { key: "quantity", label: "Liter", aliases: ["liter", "volym", "quantity", "antal"] }, { key: "amount", label: "Bränslekostnad", required: true, aliases: ["belopp", "summa", "kostnad", "bränslekostnad", "amount"] }],
  },
  vehicle_activity: {
    label: "Fordonens beläggning",
    description: "Tillgänglig och belagd tid per fordon och dag.",
    fields: [...shared, { key: "available_hours", label: "Tillgängliga timmar", required: true, aliases: ["tillgängliga timmar", "kapacitet", "available hours", "möjliga timmar"] }, { key: "occupied_hours", label: "Belagda timmar", required: true, aliases: ["belagda timmar", "bokade timmar", "aktiv tid", "occupied hours"] }],
  },
  driver_time: {
    label: "Chaufförstid",
    description: "Betalda och debiterbara timmar per chaufför.",
    fields: [
      { key: "occurred_on", label: "Datum", required: true, aliases: ["datum", "date", "dag", "period"] },
      { key: "employee_number", label: "Anställningsnummer", required: true, aliases: ["anställningsnummer", "anst nr", "anstnr", "förare", "chaufför", "employee number"] },
      { key: "paid_hours", label: "Betalda timmar", required: true, aliases: ["betalda timmar", "arbetade timmar", "total tid", "paid hours", "timmar"] },
      { key: "billable_hours", label: "Debiterbara timmar", required: true, aliases: ["debiterbara timmar", "fakturerbara timmar", "debiterad tid", "billable hours"] },
      { key: "description", label: "Beskrivning", aliases: ["beskrivning", "aktivitet", "tidkod", "description"] },
    ],
  },
};

export function suggestMapping(headers: string[], kind: DataKind) {
  const normalized = headers.map((header) => ({ header, value: header.toLocaleLowerCase("sv").replace(/[_-]+/g, " ").trim() }));
  return Object.fromEntries(DATA_KINDS[kind].fields.map((field) => {
    const match = normalized.find(({ value }) => field.aliases.some((alias) => value === alias || value.includes(alias)));
    return [field.key, match?.header ?? ""];
  }));
}
