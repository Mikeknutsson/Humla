import { PDFDocument, StandardFonts, rgb } from 'pdf-lib';
import type { InternalCenterSummary } from './internal-center-summary';
import { elleholmsLogoJpeg } from './internal-economy-logo';
import { internalEconomyPdf, type EconomyRow, type InternalEconomyReport } from './internal-economy-pdf';
import { internalPrintBlock, internalPrintBlocks } from './internal-print-blocks';

const total = (values: number[]) => values.reduce((sum, value) => sum + Math.round(value * 100), 0) / 100;

function summarize(rows: EconomyRow[]) {
  const priced = rows.flatMap(row => row.amount === null ? [] : [row.amount]);
  const debits = rows.flatMap(row => row.debit_amount === null ? [] : [row.debit_amount]);
  const categoryTotal = (...categories: string[]) => total(rows.filter(row => categories.includes(row.category)).map(row => row.amount ?? 0));
  return {
    rows: rows.length,
    missing_rows: rows.length - priced.length,
    total: rows.length === priced.length ? total(priced) : null,
    priced_amount: total(priced),
    debit_amount: debits.length ? total(debits) : null,
    discount_amount: total(rows.map(row => row.discount_amount ?? 0)),
    transport: categoryTotal('transport'),
    material: rows.some(row => row.category === 'material' && row.amount === null) ? null : categoryTotal('material'),
    tipp_deponi: categoryTotal('tipp_deponi', 'workshop'),
  };
}

export async function internalPrintReport(economy: InternalEconomyReport, summary: InternalCenterSummary, selected: string) {
  const sections = internalPrintBlocks.filter(block => selected === 'all' || block.id === selected).map(block => ({
    ...block,
    pairs: summary.transfers.filter(pair => pair.rows.length && internalPrintBlock(pair.fromCenter, pair.toCenter) === block.id)
      .sort((a, b) => a.fromCenter.localeCompare(b.fromCenter) || a.toCenter.localeCompare(b.toCenter)),
  }));
  if (!sections.some(section => section.pairs.length)) return null;

  const pdf = await PDFDocument.create();
  const cover = pdf.addPage([842, 595]);
  const gross = pdf.addPage([842, 595]);
  let summaryPage = cover;
  const font = await pdf.embedFont(StandardFonts.Helvetica);
  const bold = await pdf.embedFont(StandardFonts.HelveticaBold);
  const logo = await pdf.embedJpg('data:image/jpeg;base64,' + elleholmsLogoJpeg);
  const dark = rgb(.08, .09, .1), white = rgb(1, 1, 1), yellow = rgb(1, .94, .72), gray = rgb(.95, .96, .96);
  const currency = new Intl.NumberFormat('sv-SE', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  const money = (amount: number | null) => amount === null ? 'Pris saknas' : currency.format(amount).replace('−', '-') + ' kr';
  const text = (value: string, x: number, y: number, face = font, color = dark, size = 10) =>
    summaryPage.drawText(value, { x, y, font: face, color, size });
  const right = (value: string, x: number, y: number, color = dark) =>
    text(value, x - bold.widthOfTextAtSize(value, 10), y, bold, color);
  const band = (y: number, height: number, color: typeof dark) =>
    summaryPage.drawRectangle({ x: 24, y, width: 794, height, color });

  function summaryHeader(title: string, amountLabel: string) {
    summaryPage.drawImage(logo, { x: 24, y: 537, width: 173, height: 47 });
    text('Internöverföring - underlag till ekonomi', 230, 565, bold, dark, 15);
    text(title, 230, 546, bold);
    text(`${economy.period.from} - ${economy.period.to} | SEK exklusive moms`, 230, 530, font, dark, 8);
    band(516, 3, rgb(1, .82, .05));
    text('Från (belastas)', 36, 488, bold);
    text('Till (krediteras)', 300, 488, bold);
    right(amountLabel, 714, 488);
    text('Underlag', 751, 488, bold);
  }

  summaryHeader('Överföringsunderlag - netto per kostnadsställe', 'Netto exkl. moms');
  const grossSections = sections.map(section => ({
    title: section.title,
    rows: [] as { from: string; to: string; amount: number | null; page: number }[],
  }));

  let y = 468;
  const allAmounts: (number | null)[] = [];
  for (const [index, section] of sections.entries()) {
    band(y - 6, 18, dark);
    text(section.title, 36, y, bold, white);
    const headerY = y;
    const amounts: (number | null)[] = [];
    const netPairs = new Map<string, { from: string; to: string; cents: number; missing: boolean; pages: number[] }>();
    y -= 18;
    if (!section.pairs.length) {
      text('Inga överföringar i vald period', 36, y);
      y -= 18;
    }
    for (const pair of section.pairs) {
      const workshop = pair.toCenter === '40';
      const economyPriced = pair.fromCenter === '10' && ['20', '30'].includes(pair.toCenter);
      const rows: EconomyRow[] = economyPriced
        ? economy.rows.filter(row => row.from_center === pair.fromCenter && row.to_center === pair.toCenter)
        : pair.rows.map(row => ({
          ...row, order_status: '', driver: '', from_center: pair.fromCenter, to_center: pair.toCenter,
          rate: null, original_amount: row.amount ?? 0, debit_amount: workshop ? null : row.amount,
          discount_amount: null, price_status: '', price_basis: workshop ? 'Next 4630' : 'Workify',
          estimated: false, preliminary: row.report_basis === 'preliminary', component: 'original',
        }));
      if (!rows.length) throw new Error('Ekonomirader saknas för ett överföringspar');
      const subtotals = summarize(rows);
      const from = pair.fromCenter + ' ' + pair.fromName, to = pair.toCenter + ' ' + pair.toName;
      const forward = pair.fromCenter < pair.toCenter;
      const key = [pair.fromCenter, pair.toCenter].sort().join('-');
      const net = netPairs.get(key) ?? {
        from: forward ? from : to, to: forward ? to : from, cents: 0, missing: false, pages: [],
      };
      net.cents += (forward ? 1 : -1) * Math.round((subtotals.total ?? 0) * 100);
      net.missing ||= subtotals.total === null;
      const detailPage = pdf.getPageCount() + 1;
      net.pages.push(detailPage);
      grossSections[index].rows.push({ from, to, amount: subtotals.total, page: detailPage });
      netPairs.set(key, net);

      const byProject = new Map<string, EconomyRow[]>();
      for (const row of rows) {
        const key = row.project || row.littra || '';
        const projectRows = byProject.get(key) ?? [];
        projectRows.push(row);
        byProject.set(key, projectRows);
      }
      const projects = [...byProject].sort(([a], [b]) => a.localeCompare(b, 'sv', { numeric: true })).map(([project, rr]) => ({
        center: pair.toCenter, project, name: rr.find(row => row.littra)?.littra || '', ...summarize(rr),
      }));
      const detail = await PDFDocument.load(await internalEconomyPdf({
        ...economy, rows, projects, centers: [{ center: pair.toCenter, ...subtotals }],
      }, {
        title: `Till ${to} från ${from}`, workshop,
        note: workshop ? 'Källa: Next, upparbetad intäkt på konto 4630. Gult streck = preliminär rad.'
          : economyPriced ? 'Material till självkostnad. Matjord behåller fullt pris. Gult streck = preliminär rad.'
            : 'Källa: Workify i Humla. Gult streck = preliminär rad.',
      }));
      for (const page of await pdf.copyPages(detail, detail.getPageIndices())) pdf.addPage(page);
    }
    for (const net of netPairs.values()) {
      const amount = net.missing ? null : Math.abs(net.cents) / 100;
      amounts.push(amount);
      allAmounts.push(amount);
      band(y - 6, 18, gray);
      if (amount === null || amount === 0) {
        text(net.from + ' / ' + net.to, 36, y);
      } else {
        text(net.cents > 0 ? net.from : net.to, 36, y);
        text(net.cents > 0 ? net.to : net.from, 300, y);
      }
      right(amount === 0 ? 'Ingen överföring' : money(amount), 714, y);
      text((net.pages.length > 1 ? 'S. ' : 'Sida ') + net.pages.join(', '), 751, y);
      y -= 18;
    }
    if (section.id === 'workshop' && amounts.length) {
      right(money(amounts.some(v => v === null) ? null : total(amounts as number[])), 714, headerY, white);
    }
    y -= 6;
  }
  band(y - 7, 22, yellow);
  text('Totalt att överföra efter kvittning', 36, y, bold);
  right(money(allAmounts.some(v => v === null) ? null : total(allAmounts as number[])), 714, y);
  text('Belopp i motsatta riktningar kvittas per kostnadsställepar. Se sida 2 för beloppen före kvittning.', 24, y - 28, font, dark, 9);
  text('Elleholms Maskin AB | Underlag för ekonomi', 24, 22, font, dark, 8);
  summaryPage = gross;
  summaryHeader('Sammanställning före kvittning - brutto per riktning', 'Brutto exkl. moms');
  y = 468;
  const grossAmounts: (number | null)[] = [];
  for (const section of grossSections) {
    band(y - 6, 18, dark);
    text(section.title, 36, y, bold, white);
    y -= 18;
    if (!section.rows.length) {
      text('Inga överföringar i vald period', 36, y);
      y -= 18;
    }
    for (const row of section.rows) {
      grossAmounts.push(row.amount);
      band(y - 6, 18, gray);
      text(row.from, 36, y);
      text(row.to, 300, y);
      right(money(row.amount), 714, y);
      text('Sida ' + row.page, 751, y);
      y -= 18;
    }
    y -= 6;
  }
  band(y - 7, 22, yellow);
  text('Totalt före kvittning', 36, y, bold);
  right(money(grossAmounts.some(v => v === null) ? null : total(grossAmounts as number[])), 714, y);
  text('Se sida 1 för nettobeloppen som ska föras över.', 24, y - 28, font, dark, 9);
  text('Elleholms Maskin AB | Underlag för ekonomi', 24, 22, font, dark, 8);
  for (const [index, page] of pdf.getPages().entries()) {
    page.drawText(`Sida ${index + 1} / ${pdf.getPageCount()}`, { x: 748, y: 22, size: 7, font });
  }
  pdf.setTitle('Internöverföring - underlag till ekonomi');
  pdf.setAuthor('Elleholms Maskin AB');
  return pdf.save();
}
