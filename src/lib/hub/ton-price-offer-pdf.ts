import {PDFDocument, StandardFonts, rgb, type PDFPage} from 'pdf-lib';
import {elleholmsLogoJpeg} from '@/lib/kpi/internal-economy-logo';
import {offerMoney, type OfferDetails, type OfferLine} from './ton-price-offer';
import type {DeliveryPlanLine} from './ton-price-delivery-plan';

const ink = rgb(.08,.11,.10);
const muted = rgb(.31,.37,.35);
const line = rgb(.82,.85,.84);
const green = rgb(.09,.29,.22);
const white = rgb(1,1,1);
const clean = (text: string) => text.replace(/[\u2010-\u2015\u2212]/g,'-').replace(/[^\u0020-\u007e\u00a0-\u00ff]/g,' ').trim();
const left = 44;
const right = 551;

export async function tonPriceOfferPdf(delivery: string, date: string, details: OfferDetails, lines: OfferLine[], plan?: DeliveryPlanLine[], priceDate?: string) {
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
    const title = plan ? 'Leveransplan' : 'Offert';
    text(title,right-bold.widthOfTextAtSize(title,22),778,22,true,green);
    number(date,right,758,false,muted);
    page.drawRectangle({x:left,y:736,width:right-left,height:3,color:rgb(1,.82,.05)});
    y = 714;
  }

  const priceEdge = right-9;
  function heading() {
    page.drawRectangle({x:left,y:y-7,width:right-left,height:24,color:green});
    text('Fraktion',left+8,y,10,true,white);
    number('Levererat pris (kr/ton)',priceEdge,y,true,white);
    y -= 24;
  }

  function field(label: string, value: string, indent = 0) {
    if (!value.trim()) return;
    const rows = wrapped(value,right-left-126-indent);
    if (y - rows.length*14 < 58) newPage();
    text(label,left+indent,y,9,true,muted);
    rows.forEach((row,index) => text(row,left+126+indent,y-index*14));
    y -= Math.max(1,rows.length)*14+5;
  }

  newPage();
  if (plan) {
    field('Dokument', 'Internt underlag för transportledning');
    field('Prisdatum', priceDate ?? date);
    field('Kund', details.customer);
    field('Projekt', details.project);
    for (const row of plan) {
      const title = wrapped(row.material,right-left-16,11);
      const krPerTon = (price: number) => offerMoney.format(price)+' kr/ton';
      const adjustment = row.materialPrice - row.purchase;
      const fields = [
        ['Hämta från',row.pickup],
        [row.tippingDestination ? 'Tippa på' : 'Leverera till',row.delivery],
        ['Ekipage och runda',row.route],
        ['Returlast',row.returnLoad],
        [row.tip ? 'Tippavgift' : 'Materialinköp',krPerTon(row.purchase)],
        [row.tip ? 'Justering av tippavgift' : 'Materialpåslag',adjustment ? krPerTon(adjustment) : ''],
        [row.tip ? 'Tippavgift i offerten' : 'Material inkl. påslag',krPerTon(row.materialPrice)],
        ['Transport',krPerTon(row.freight)],
        ['Tillägg enkelbil',row.truckSupplement === null ? 'Pris beräknas separat' : krPerTon(row.truckSupplement)],
        ['Pris i offerten',krPerTon(row.unitPrice)],
      ];
      const height = fields.reduce((sum,[,value]) => sum + (value.trim() ? wrapped(value,right-left-134).length*14+5 : 0),title.length*14+15);
      if (y - height < 58) newPage();
      y -= 7;
      page!.drawRectangle({x:left,y:y-title.length*14+7,width:right-left,height:title.length*14+9,color:green});
      title.forEach((value,index) => text(value,left+8,y-index*14,11,true,white));
      y -= title.length*14+8;
      for (const [label,value] of fields) field(label,value,8);
    }
  } else {
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
      const rows = wrapped(item.quotedVehicle ? item.material+' · '+item.quotedVehicle : item.material,priceEdge-left-150);
      const height = Math.max(24,rows.length*14+10);
      if (y-height < 64) {newPage();heading();}
      rows.forEach((row,index) => text(row,left+8,y-index*14));
      number(offerMoney.format(item.unitPrice),priceEdge,y,true);
      page!.drawLine({start:{x:left,y:y-height+14},end:{x:right,y:y-height+14},color:line,thickness:.6});
      y -= height;
    }

    if (y < 134) newPage();
    y -= 9;
    text('Tillägg enkelbil',left,y,13,true,green);
    y -= 18;
    text('Gäller när bil + släp ersätts med enkelbil.',left,y,9,false,muted);
    y -= 23;
    for (const item of lines) {
      const rows = wrapped(item.material,priceEdge-left-150);
      const height = Math.max(24,rows.length*14+10);
      if (y-height < 64) {
        newPage();
        text('Tillägg enkelbil',left,y,13,true,green);
        y -= 24;
      }
      rows.forEach((row,index) => text(row,left+8,y-index*14));
      number(item.truckSupplement === null ? 'Beräknas separat' : offerMoney.format(item.truckSupplement)+' kr/ton',priceEdge,y,true);
      y -= height;
    }

    const terms = wrapped(details.terms,right-left);
    if (terms.length && y - terms.length*14 < 64) newPage();
    terms.forEach((row,index) => text(row,left,y-index*14));
  }

  const pages = pdf.getPages();
  pages.forEach((item,index) => {
    page = item;
    text(plan ? 'Elleholms Maskin AB  |  Internt  |  Priser i SEK exkl. moms' : 'Elleholms Maskin AB  |  Priser i SEK exkl. moms',left,36,9,false,muted);
    number(`${index+1} / ${pages.length}`,right,36,false,muted);
  });
  pdf.setTitle(plan ? 'Leveransplan - internt underlag' : 'Offert - material och transport');
  pdf.setAuthor('Elleholms Maskin AB');
  return pdf.save();
}
