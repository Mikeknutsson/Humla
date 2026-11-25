export const sawArticles = ['12-04','12-041'] as const;
export type SawArticle = typeof sawArticles[number];
export type SawInvoiceRow = {
  invoice: string; row: string; date: string; article: SawArticle; amount: number;
  credit: boolean; customer: string; reference: string;
};
type RecordValue = Record<string,unknown>;
export type SawInvoiceCoverage = {from: string; to: string; rows: SawInvoiceRow[]};

const asObject = (value: unknown): RecordValue =>
  value && typeof value === 'object' && !Array.isArray(value) ? value as RecordValue : {};
const asText = (value: unknown) => typeof value === 'string' || typeof value === 'number' ? String(value).trim() : '';
const asMoney = (input: unknown) => {
  const value = asText(input);
  return value && /^-?\d+(?:[.,]\d+)?$/.test(value) ? Number(value.replace(',','.')) : NaN;
};
const isCredit = (value: unknown) => value === true || /^(?:1|J|JA|Y|YES|TRUE|CREDIT)$/i.test(asText(value));

export async function fetchSawInvoices(get: (path: string) => Promise<unknown>, from: string, to: string): Promise<SawInvoiceCoverage> {
  const documents = new Set<string>();
  for (const article of sawArticles) {
    let page = 1;
    let totalPages = 1;
    do {
      const params = new URLSearchParams({fromdate:from,todate:to,articlenumber:article,limit:'100',page:String(page)});
      const response = asObject(await get('invoices?'+params));
      if (!Array.isArray(response.Invoices)) throw Error('Fortnox returnerade ingen fakturalista.');
      const meta = asObject(response.MetaInformation);
      totalPages = meta['@TotalPages'] == null
        ? page + (response.Invoices.length === 100 ? 1 : 0)
        : Number(meta['@TotalPages']);
      if (!Number.isInteger(totalPages) || totalPages < 0 || totalPages > 100 || (totalPages === 0 && response.Invoices.length)) {
        throw Error('Fortnox returnerade ogiltig sidinformation.');
      }
      if (meta['@CurrentPage'] != null && Number(meta['@CurrentPage']) !== page && totalPages > 0) {
        throw Error('Fortnox returnerade en annan sida än den begärda.');
      }
      for (const item of response.Invoices) {
        const invoice = asObject(item);
        const id = asText(invoice.DocumentNumber);
        if (!id) throw Error('En Fortnoxfaktura saknar fakturanummer.');
        if (invoice.Cancelled === true || invoice.Booked === false) continue;
        documents.add(id);
      }
      page++;
    } while (page <= totalPages);
  }

  const rows: SawInvoiceRow[] = [];
  for (const id of documents) {
    const invoice = asObject(asObject(await get('invoices/'+encodeURIComponent(id))).Invoice);
    if (asText(invoice.DocumentNumber) !== id || !Array.isArray(invoice.InvoiceRows)
      || typeof invoice.Booked !== 'boolean' || typeof invoice.Cancelled !== 'boolean') {
      throw Error('Fortnox returnerade ofullständiga fakturauppgifter.');
    }
    if (!invoice.Booked || invoice.Cancelled) continue;
    const date = asText(invoice.InvoiceDate);
    if (!/^\d{4}-\d{2}-\d{2}$/.test(date) || date < from || date > to) throw Error('Fakturadatum ligger utanför kontrollperioden.');
    const credit = isCredit(invoice.Credit) || asMoney(invoice.Net) < 0;
    const invoiceRows = invoice.InvoiceRows.map(asObject);
    const net = (row: RecordValue) => asMoney(row.TotalExcludingVAT ??
      (invoice.VATIncluded === false ? row.Total : undefined));
    const signedTotal = invoiceRows.reduce((sum,row) => sum+(net(row) || 0),0);
    const creditSign = credit && signedTotal > 0 ? -1 : 1;
    for (const [index,row] of invoiceRows.entries()) {
      const article = sawArticles.find(article => article === asText(row.ArticleNumber));
      if (!article) continue;
      if (asText(invoice.Currency).toUpperCase() !== 'SEK') throw Error('Kontrollen innehåller en faktura i annan valuta än SEK.');
      const amount = net(row);
      if (!Number.isFinite(amount)) throw Error('En artikelrad saknar belopp exklusive moms.');
      rows.push({invoice:id,row:asText(row.RowId) || String(index+1),date,article,
        amount:Math.round(amount*creditSign*100)/100,credit,
        customer:asText(invoice.CustomerName),
        reference:asText(invoice.YourOrderNumber) || asText(invoice.OrderReference)});
    }
  }
  rows.sort((a,b) => a.date.localeCompare(b.date) || a.invoice.localeCompare(b.invoice,'sv',{numeric:true}));
  return {from,to,rows};
}
