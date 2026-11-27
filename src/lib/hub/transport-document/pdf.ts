import {randomUUID} from 'node:crypto';
import {PDFDocument, StandardFonts, rgb, type PDFFont, type PDFPage} from 'pdf-lib';
import {elleholmsLogoJpeg} from '../../kpi/internal-economy-logo';
import {municipalityOptions, type DocumentFields, type Location, type Party} from './fields';

const width = 595.28;
const height = 841.89;
const margin = 38;
const contentWidth = width - 2 * margin;
const black = rgb(0.14,0.14,0.14);
const grey = rgb(0.34,0.35,0.36);
const line = rgb(0.83,0.83,0.82);
const soft = rgb(0.96,0.96,0.95);
const gold = rgb(0.98,0.77,0.12);
const white = rgb(1,1,1);
const limit = height - 67;
const formatKg = new Intl.NumberFormat('sv-SE',{maximumFractionDigits:3});
const municipalities = new Map(municipalityOptions);

export class DocumentTextError extends Error {}

function wrap(value: string, font: PDFFont, size: number, available: number) {
  try { font.encodeText(value); } catch {
    throw new DocumentTextError(`PDF:en kan inte skriva alla tecken i ”${value.slice(0,40)}”. Kontrollera fältet.`);
  }
  const rows: string[] = [];
  let row = '';
  for (let word of value.split(' ')) {
    if (font.widthOfTextAtSize(row ? row+' '+word : word,size) <= available) {
      row = row ? row+' '+word : word;
      continue;
    }
    if (row) rows.push(row);
    while (font.widthOfTextAtSize(word,size) > available) {
      let end = 1;
      while (end < word.length && font.widthOfTextAtSize(word.slice(0,end+1),size) <= available) end += 1;
      rows.push(word.slice(0,end));
      word = word.slice(end);
    }
    row = word;
  }
  if (row) rows.push(row);
  return rows;
}

export async function renderTransportDocument(fields: DocumentFields) {
  const pdf = await PDFDocument.create();
  const [normal,bold,logo] = await Promise.all([
    pdf.embedFont(StandardFonts.Helvetica),
    pdf.embedFont(StandardFonts.HelveticaBold),
    pdf.embedJpg('data:image/jpeg;base64,' + elleholmsLogoJpeg),
  ]);
  const hazardous = fields.waste.some(row => row.code.endsWith('*'));
  const subtitle = hazardous ? 'Farligt avfall' : 'Avfall';
  const documentId = randomUUID().replaceAll('-','').slice(0,12).toUpperCase();
  let page: PDFPage;
  let y = 0;

  function text(value: string, x: number, top: number, size: number, font = normal, color = black) {
    if (!value) return;
    page.drawText(value,{x,y:height-top-size,size,font,color});
  }
  function box(x: number, top: number, w: number, h: number, color = soft) {
    page.drawRectangle({x,y:height-top-h,width:w,height:h,color});
  }
  function rule(x: number, top: number, w: number, color = line, thickness = 0.8) {
    page.drawLine({start:{x,y:height-top},end:{x:x+w,y:height-top},thickness,color});
  }

  function newPage(first = false) {
    page = pdf.addPage([width,height]);
    const logoWidth = first ? 148 : 113;
    const mark = logo.scale(logoWidth / logo.width);
    page.drawImage(logo,{x:margin,y:height-30-mark.height,width:mark.width,height:mark.height});
    const dateX = width-margin-104;
    text('TRANSPORTDATUM',dateX,32,8,bold,grey);
    text(fields.date,dateX,45,14,bold);
    text(`Dokument ${documentId}`,dateX,63,7,normal,grey);
    box(margin,first ? 84 : 74,contentWidth,3,gold);
    if (first) {
      text('Transportdokument',margin,99,30,bold);
      text(subtitle,margin,137,13,normal,grey);
      y = 164;
    } else {
      text(`Transportdokument för ${subtitle.toLocaleLowerCase('sv')} – fortsättning`,margin,90,14,bold);
      y = 116;
    }
  }

  function room(amount: number) {
    if (y + amount > limit) newPage();
  }

  function heading(label: string) {
    text(label,margin,y,15,bold);
    y += 24;
  }

  function cardGrid(title: string, cards: {label: string; lines: [string, boolean][]}[]) {
    const gap = 8;
    const column = (contentWidth - (cards.length-1)*gap) / cards.length;
    const layouts = cards.map(card => card.lines.flatMap(([value,heading]) =>
      wrap(value,heading ? bold : normal,heading ? 10 : 9,column-22).map(row => ({row,heading}))));
    const h = 38 + Math.max(...layouts.map(rows => rows.length * 13));
    room(h + 24);
    heading(title);
    layouts.forEach((rows,i) => {
      const x = margin + i*(column+gap);
      box(x,y,column,h);
      text(cards[i].label,x+11,y+9,8,bold,grey);
      rows.forEach(({row,heading},j) => text(row,x+11,y+24+j*13,heading ? 10 : 9,heading ? bold : normal));
    });
    y += h + 17;
  }

  const place = (label: string, location: Location): Parameters<typeof cardGrid>[1][number] => ({
    label,lines:[[location.value,true], ...(location.municipality
      ? [[`${municipalities.get(location.municipality)} (${location.municipality})`,false] as [string, boolean]] : [])],
  });
  const party = (label: string, value: Party): Parameters<typeof cardGrid>[1][number] => ({
    label,lines:[[value.name,true],[value.address,false],[value.organisation,false]],
  });

  newPage(true);
  const references: [string,string][] = [['Projekt',fields.project],['Fordon',fields.registration],
    ['Inleveransnummer',fields.deliveryNumber],['ADR-handlingens referens',fields.adrReference]];
  const visibleReferences = references.filter(([,value]) => value);
  if (visibleReferences.length) {
    const rows = wrap(visibleReferences.map(([label,value]) => `${label} ${value}`).join('  |  '),normal,9,contentWidth);
    rows.forEach((row,i) => text(row,margin,y+i*13,9,normal,grey));
    y += rows.length*13 + 11;
  }

  cardGrid('Transportsträcka',[place('HÄMTPLATS',fields.origin),place('SLUTLIG MOTTAGNINGSPLATS',fields.destination)]);
  cardGrid('Parter',[party('TRANSPORTÖR',fields.carrier),...(fields.consignor ? [party('LÄMNARE',fields.consignor)] : []),
    party('SLUTLIG MOTTAGARE',fields.receiver)]);

  const packaging = fields.waste.some(row => row.packages || row.packaging);
  const codeWidth = 76;
  const weightWidth = 90;
  const packagingWidth = packaging ? 100 : 0;
  const xDescription = margin + codeWidth;
  const xPackaging = width - margin - 2*weightWidth - packagingWidth;
  const right = width - margin - 10;

  function rightAligned(value: string, edge: number, top: number, size: number, color = black) {
    text(value,edge-bold.widthOfTextAtSize(value,size),top,size,bold,color);
  }

  function tableHeader() {
    heading('Avfall som transporteras');
    box(margin,y,contentWidth,24,black);
    text('Avfallskod',margin+10,y+7,9,bold,white);
    text('Benämning',xDescription,y+7,9,bold,white);
    if (packaging) text('Kollin / emballage',xPackaging,y+7,9,bold,white);
    rightAligned('Uppskattad vikt (kg)',right-weightWidth,y+7,9,white);
    rightAligned('Invägt kg',right,y+7,9,white);
    y += 24;
  }

  const waste = fields.waste.map(row => {
    const description = wrap(row.name,normal,10,xPackaging-xDescription-12);
    const packageLabel = [row.packages ? `${row.packages} kollin` : '',row.packaging].filter(Boolean).join(' / ');
    const packs = packaging && packageLabel ? wrap(packageLabel,normal,9,packagingWidth-12) : [];
    return {row,description,packs,h:Math.max(29,Math.max(description.length,packs.length)*13+12)};
  });
  room(48+waste[0].h);
  tableHeader();
  waste.forEach(({row,description,packs,h},i) => {
    if (y+h > limit) {
      newPage();
      tableHeader();
    }
    if (i%2 === 0) box(margin,y,contentWidth,h);
    text(row.code,margin+10,y+8,10,bold);
    description.forEach((item,j) => text(item,xDescription,y+8+j*13,10));
    packs.forEach((item,j) => text(item,xPackaging,y+8+j*13,9));
    if (row.estimatedKg) rightAligned(formatKg.format(Number(row.estimatedKg)),right-weightWidth,y+8,10);
    if (row.weighedKg) rightAligned(formatKg.format(Number(row.weighedKg)),right,y+8,10);
    else rule(right-64,y+21,64,grey);
    rule(margin,y+h,contentWidth);
    y += h;
  });

  y += 20;
  const signers = [{label:'Transportör',name:fields.carrierSigner},
    ...(fields.consignor ? [{label:'Lämnare',name:fields.consignorSigner}] : [])];
  const gap = 20;
  const signWidth = (contentWidth-(signers.length-1)*gap) / signers.length;
  const signerLines = signers.map(({name}) => wrap(
    name ? `Namnförtydligande  ${name}` : 'Namnförtydligande __________________________',normal,8,signWidth));
  const signingHeight = 62 + Math.max(...signerLines.map(rows => rows.length))*10;
  room(24 + signingHeight);
  heading('Underskrifter före avfärd');
  signers.forEach(({label},i) => {
    const x = margin+i*(signWidth+gap);
    text(label,x,y,10,bold);
    rule(x,y+42,signWidth,grey);
    text('Underskrift',x,y+47,8,normal,grey);
    signerLines[i].forEach((row,j) => text(row,x,y+62+j*10,8,normal,grey));
  });

  y += signingHeight + 20;
  room(85);
  heading('Mottagningskvittens vid lossning (frivillig)');

  const receiptFields = (labels: string[], top: number, writingHeight: number) => {
    const fieldWidth = (contentWidth - (labels.length - 1)*gap) / labels.length;
    labels.forEach((label,i) => {
      const x = margin + i*(fieldWidth+gap);
      text(label,x,top,8,bold,grey);
      rule(x,top+writingHeight,fieldWidth,grey);
    });
  };
  receiptFields(['Datum','Invägd totalvikt (kg)','Vågsedelsnummer'],y,24);
  receiptFields(['Mottagarens underskrift','Namnförtydligande'],y+32,28);

  const pages = pdf.getPages();
  pages.forEach((p,i) => {
    page = p;
    rule(margin,height-53,contentWidth);
    text('Elleholms Maskin AB  |  Karlshamnsvägen 329, 294 93 Sölvesborg',margin,height-41,8,normal,grey);
    text(hazardous ? '6 kap. 19 § avfallsförordningen (2020:614) och NFS 2022:2' : 'Transportdokument',margin,height-29,7,normal,grey);
    const number = `${i+1} / ${pages.length}`;
    text(number,width-margin-normal.widthOfTextAtSize(number,8),height-41,8,normal,grey);
  });
  pdf.setTitle('Transportdokument – Elleholms Maskin AB');
  pdf.setAuthor('Elleholms Maskin AB');
  return pdf.save();
}
