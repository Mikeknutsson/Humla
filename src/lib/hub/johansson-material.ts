import * as XLSX from 'xlsx';

export type Load = {
  sheet: string;
  row: number;
  ticket: string;
  quarry: string;
  date: string;
  registration: string;
  order: string;
  article: string;
  fraction: string;
  kg: number;
};
export type Invoice = {
  name: string;
  loads: Load[];
  issues: string[];
};
export type CheckedLoad = Load & {
  match: 'matched' | 'equivalent' | 'order_missing' | 'article_missing' | 'order_unspecified';
  workify_articles: string[];
  workify_rates?: number[];
  workify_receipts?: {reference: string | null; date: string | null}[];
  workify_article_date?: string | null;
  workify_combined?: {kg: number; workify_kg: number; load_count: number; date?: string | null} | null;
  workify_registrations: string[];
  excel_registration: string;
  rate: number | null;
  amount: number | null;
  price_source: string | null;
};

const label = (value: unknown) => String(value ?? '').trim();
const key = (value: unknown) => label(value).toLocaleLowerCase('sv').replace(/[^a-zåäö0-9]/g, '');
const ticketNumber = (value: unknown) => /^\d+$/.test(label(value));
const column = (row: unknown[], names: string[]) => row.findIndex(value => names.includes(key(value)));

function deliveryDate(value: unknown, date1904: boolean) {
  if (typeof value === 'number') {
    const date = XLSX.SSF.parse_date_code(value, {date1904});
    if (date && date.y >= 2000 && date.y <= 2100) {
      return [date.y, String(date.m).padStart(2, '0'), String(date.d).padStart(2, '0')].join('-');
    }
  }
  const iso = label(value).match(/^(20\d{2})[-/.](\d{1,2})[-/.](\d{1,2})(?:\s|T|$)/);
  const swedish = label(value).match(/^(\d{1,2})[-/.](\d{1,2})[-/.](20\d{2})(?:\s|$)/);
  const parts = iso?.slice(1) ?? swedish?.slice(1).reverse();
  if (!parts) return '';
  const [year, month, day] = parts.map(Number);
  const date = new Date(Date.UTC(year, month - 1, day));
  return date.getUTCMonth() === month - 1 && date.getUTCDate() === day ? date.toISOString().slice(0, 10) : '';
}

export function parseJohanssonWorkbook(bytes: Uint8Array) {
  const workbook = XLSX.read(bytes, {type: 'array', sheetRows: 6001});
  const invoices: Invoice[] = [];
  const skipped: string[] = [];
  const seen = new Set<string>();
  let count = 0;
  if (workbook.SheetNames.length > 100) throw Error('Arbetsboken har för många flikar.');
  for (const name of workbook.SheetNames) {
    const sheet = workbook.Sheets[name];
    if (!sheet['!ref']) { skipped.push(name); continue; }
    const range = XLSX.utils.decode_range(sheet['!fullref'] ?? sheet['!ref']);
    if (range.e.r >= 6000 || range.e.c >= 150) throw Error('En flik är för stor för materialkontrollen.');
    const rows = XLSX.utils.sheet_to_json<unknown[]>(sheet, {header: 1, range: 0, blankrows: true});
    const invoice: Invoice = {name, loads: [], issues: []};
    let headings: {ticket: number; date: number; plate: number; order: number; article: number; weight: number; quarry: number; tonnes: boolean} | undefined;
    let defaultQuarry = '';
    let recognized = false;
    for (const [index, row] of rows.entries()) {
      if (key(row[0]) === 'anläggning' && label(row[2])) defaultQuarry = label(row[2]).split(/\s+-\s+/)[0];
      const ticket = column(row, ['transnr', 'transaktionsnr', 'transaktionsnummer', 'vågsedel']);
      const date = column(row, ['datum', 'leveransdatum', 'vägningsdatum']);
      const plate = column(row, ['regnr', 'registreringsnr', 'registreringsnummer']);
      const order = column(row, ['ordernr', 'ordernummer', 'workifyordernummer']);
      const article = column(row, ['artikel', 'artikelnamn', 'material']);
      const weight = column(row, ['nettokg', 'nettoviktkg', 'viktkg', 'nettoviktton', 'nettoton', 'viktton']);
      if (ticket >= 0 && date >= 0 && plate >= 0 && article >= 0 && weight >= 0) {
        headings = {ticket, date, plate, order, article, weight, quarry: column(row, ['anläggning', 'täkt']), tonnes: key(row[weight]).endsWith('ton')};
        recognized = true;
        continue;
      }
      if (!headings) continue;
      const offsetTicket = headings.date === headings.ticket + 2 && ticketNumber(row[headings.ticket + 1]);
      const transaction = label(row[headings.ticket + Number(offsetTicket)]);
      const articleName = label(row[headings.article]);
      const day = deliveryDate(row[headings.date], !!workbook.Workbook?.WBProps?.date1904);
      if (!transaction && !day) continue;
      if (/^totalt?\b|^summa\b/i.test(articleName)) continue;
      if (!ticketNumber(transaction) && !day) continue;
      const weightText = label(row[headings.weight]).replace(/\s/g, '').replace(',', '.');
      const kg = Math.round(Number(weightText) * (headings.tonnes ? 1000 : 1));
      if (!ticketNumber(transaction) || !day || !articleName || !weightText || !Number.isSafeInteger(kg) || Math.abs(kg) > 150000) {
        invoice.issues.push(`Rad ${index + 1} har ofullständigt transaktionsnummer, datum, artikel eller vikt.`);
        continue;
      }
      const quarry = (label(row[headings.quarry]) || (offsetTicket ? label(row[headings.ticket]) : '') || defaultQuarry);
      const unique = `${key(quarry).replace('kyllinge', 'kylinge')}:${transaction}`;
      if (seen.has(unique)) {
        invoice.issues.push(`Rad ${index + 1} · vägsedel ${transaction} förekommer redan i arbetsboken.`);
        continue;
      }
      seen.add(unique);
      const fraction = articleName.match(/(?<![\d/-])(\d+)\s*[/–-]\s*(\d+)(?![\d/-])/);
      invoice.loads.push({
        sheet: name, row: index + 1, ticket: transaction, quarry, date: day,
        registration: label(row[headings.plate]).toUpperCase().replace(/[^A-Z0-9]/g, ''),
        order: label(row[headings.order]), article: articleName,
        fraction: fraction ? `${Number(fraction[1])}-${Number(fraction[2])}` : '', kg,
      });
      if (++count > 3000) throw Error('Välj ett underlag med högst 3 000 materialrader.');
    }
    if (recognized && (invoice.loads.length || invoice.issues.length)) invoices.push(invoice);
    else skipped.push(name);
  }
  if (!invoices.length) throw Error('Inga transaktionsflikar kunde läsas. Kontrollera att filen är Johanssons materialunderlag.');
  return {invoices, skipped};
}
