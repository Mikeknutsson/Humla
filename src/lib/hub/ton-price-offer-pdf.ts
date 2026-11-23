import {PDFDocument, StandardFonts, rgb, type PDFPage} from 'pdf-lib';
import {elleholmsLogoJpeg} from '@/lib/kpi/internal-economy-logo';
import {offerMoney, offerQuantity, offerTotal, type OfferDetails, type offerLines} from './ton-price-offer';

const ink = rgb(.08,.11,.10);
const muted = rgb(.31,.37,.35);
const line = rgb(.82,.85,.84);
const green = rgb(.09,.29,.22);
const white = rgb(1,1,1);
const clean = (text: string) => text.replace(/[\u2010-\u2015\u2212]/g,'-').replace(/[^\u0020-\u007e\u00a0-\u00ff]/g,' ').trim();
const left = 44;
const right = 551;

export async function tonPriceOfferPdf(delivery: string, date: string, details: OfferDetails, lines: ReturnType<typeof offerLines>) {
  const pdf = await PDFDocument.create();
  const font = await pdf.embedFont(StandardFonts.Helvetica);
  const bold = await pdf.embedFont(StandardFonts.HelveticaBold);
  const logo = await pdf.embedJpg('data:image/jpeg;base64,' + elleholmsLogoJpeg);
  let page: PDFPage;
  let y = 0;

  function text(value: string, x: number, offset: number, size = 10, strong = false, color = ink) {
    page.drawText(clean(value), {x,y:offset,size,font:strong ? bold : font,color});
  }

  function wrapped(value: string, width: number, size = 10) {
    const rows: string[] = [];
    let row = '';
    for (const word of clean(value).split(/\s+/)) {
      if (row && font.widthOfTextAtSize(row + ' ' + word, size) > width) {
        rows.push(row);
        row = '';
      }
      if (row) row += ' ';
      for (const letter of word) {
        if (font.widthOfTextAtSize(row + letter, size) > width) {
          rows.push(row);
          row = '';
        }
        row += letter;
      }
    }
    if (row) rows.push(row);
    return rows;
  }

  function number(value: string, edge: number, offset: number, strong = false, color = ink) {
    const safe = clean(value);
    text(safe, edge - (strong ? bold : font).widthOfTextAtSize(safe,10), offset,10,strong,color);
  }

  function newPage() {
    page = pdf.addPage([595,842]);
    const logoSize = logo.scaleToFit(158,42);
    page.drawImage(logo,{x:left,y:755,width:logoSize.width,height:logoSize.height});
    text('Offert',right-73,778,22,true,green);
    text(date,right-73,758,10,false,muted);
    page.drawRectangle({x:left,y:736,width:right-left,height:3,color:rgb(1,.82,.05)});
    y = 714;
  }

  const columns = {tonnes:360, unit:449, amount:right-9};
  function heading() {
    page.drawRectangle({x:left,y:y-7,width:right-left,height:24,color:green});
    text('Material',left+8,y,10,true,white);
    number('Mängd (ton)',columns.tonnes,y,true,white);
    number('Lev. kr/ton',columns.unit,y,true,white);
    number('Belopp (kr)',columns.amount,y,true,white);
    y -= 24;
  }

  newPage();
  for (const [label,value] of [['Kund',details.customer],['Projekt',details.project],['Leveransplats',delivery],['Giltig till',details.validity]]) {
    if (!value.trim()) continue;
    text(label,left,y,9,true,muted);
    const rows = wrapped(value,right-left-100);
    rows.forEach((row,index) => text(row,left+100,y-index*14));
    y -= Math.max(1,rows.length)*14+5;
  }

  y -= 14;
  text('Material inklusive transport',left,y,13,true,green);
  y -= 27;
  heading();
  for (const item of lines) {
    const rows = wrapped(item.material,240);
    const height = Math.max(24,rows.length*14+10);
    if (y-height < 64) {newPage();heading();}
    rows.forEach((row,index) => text(row,left+8,y-index*14));
    number(item.tonnes === null ? '-' : offerQuantity.format(item.tonnes),columns.tonnes,y);
    number(offerMoney.format(item.unitPrice),columns.unit,y,true);
    number(item.amount === null ? '-' : offerMoney.format(item.amount),columns.amount,y);
    page!.drawLine({start:{x:left,y:y-height+14},end:{x:right,y:y-height+14},color:line,thickness:.6});
    y -= height;
  }

  const total = offerTotal(lines);
  if (total !== null) {
    if (y < 88) newPage();
    text('Totalt exkl. moms',left+8,y,11,true);
    number(offerMoney.format(total) + ' kr',columns.amount,y,true);
    y -= 24;
  }

  const terms = wrapped(details.terms,right-left);
  if (terms.length && y - terms.length*14 < 64) newPage();
  terms.forEach((row,index) => text(row,left,y-index*14));

  const pages = pdf.getPages();
  pages.forEach((item,index) => {
    page = item;
    text('Elleholms Maskin AB  |  Priser i SEK exkl. moms',left,36,9,false,muted);
    number(`${index+1} / ${pages.length}`,right,36,false,muted);
  });
  pdf.setTitle('Offert - material och transport');
  pdf.setAuthor('Elleholms Maskin AB');
  return pdf.save();
}
