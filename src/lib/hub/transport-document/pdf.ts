import {readFile} from 'node:fs/promises';
import path from 'node:path';
import {PDFDocument, StandardFonts, rgb, type PDFFont} from 'pdf-lib';
import {customReceiver, receiverOptions, type DocumentFields, type Signoff} from './fields';

// Coordinates in PDF points from the upper left of the original A4 template.
const senderColumns = [36.3,78.3,193.1,353.6,416.4,474.6,560.5];
const receiverColumns = [35,56,197.8,382.3,451.5,502.5,566.4];
const receiverRows = [172.45,184.05,205.25,230.25,251.45,262.35,274.95,289.65];
const wasteColumns = [213.6,232.7,290.4,347.1,418,467.6,517.2,559.8];
const wasteRows = [327.45,344.75,360.95,375.35,394.25,408.85,422.35,437.35,459.15,478.05,496.15,
  515.05,531.45,549.55,563.95,580.85,596.85,612.05,628.05,644.05,662.95,682.85];

const templatePath = path.join(process.cwd(),'src/lib/hub/transport-document/transport-document-template.pdf');

export async function renderTransportDocument(fields: DocumentFields) {
  const pdf = await PDFDocument.load(await readFile(templatePath));
  const page = pdf.getPage(0);
  const height = page.getHeight();
  const [normal,italic,bold] = await Promise.all([
    pdf.embedFont(StandardFonts.TimesRoman),
    pdf.embedFont(StandardFonts.TimesRomanItalic),
    pdf.embedFont(StandardFonts.TimesRomanBold),
  ]);

  function cell(value: string, x1: number, x2: number, y1: number, y2: number,
    font: PDFFont, size = 8, align: 'left' | 'center' | 'right' = 'left', multiline = false) {
    if (!value) return;
    const inset = align === 'left' ? 5.3 : 2;
    const width = x2 - x1 - inset - 2;
    // Standard PDF Times fonts use WinAnsi. Report unsupported input instead of dropping letters.
    try { font.encodeText(value); } catch {
      throw new Error(`PDF:en kan inte skriva alla tecken i ”${value.slice(0,45)}”. Kontrollera fältet.`);
    }
    const measure = (line: string) => font.widthOfTextAtSize(line,size);
    let lines = [value];
    const fits = () => lines.length * (size + 0.8) <= y2 - y1 - 0.8 && lines.every(line => measure(line) <= width);
    if (multiline && !fits()) {
      const words = value.split(' ');
      for (let split = 1; split < words.length; split++) {
        const pair = [words.slice(0,split).join(' '),words.slice(split).join(' ')];
        if (Math.max(...pair.map(measure)) < Math.max(...lines.map(measure))) lines = pair;
      }
    }
    while (!fits() && size > 5.5) size -= 0.25;
    if (!fits()) throw new Error(`”${value.slice(0,45)}” får inte plats i PDF-mallen. Korta fältet och försök igen.`);
    const lineHeight = size + 0.8;
    lines.forEach((line,index) => {
      const x = align === 'center' ? (x1 + x2 - measure(line)) / 2 :
        align === 'right' ? x2 - measure(line) - 2 : x1 + inset;
      const center = (y1 + y2) / 2 + (index - (lines.length - 1) / 2) * lineHeight;
      page.drawText(line,{x,y:height-center-size*0.26,size,font});
    });
  }

  cell(fields.createdBy, 270,561.4,53,66,normal,8,'right');
  const {sender} = fields;
  [fields.project,sender.name,sender.address,sender.organisation,sender.municipality,fields.registration].forEach((value,i) => {
    cell(value,senderColumns[i],senderColumns[i+1],118.65,143.85,italic,8,'left',true);
  });

  const lastRow = receiverOptions.length - 1;
  const receiver = fields.receiverRow === customReceiver ? fields.receiver : receiverOptions[lastRow];
  [receiver.name,receiver.address,receiver.organisation,receiver.municipality].forEach((value,i) => {
    cell(value,receiverColumns[i+1],receiverColumns[i+2],receiverRows[lastRow],receiverRows[lastRow+1],
      i === 3 ? normal : italic, i === 3 ? 8 : 9,i === 3 ? 'center' : 'left', i < 2);
  });
  const selectedRow = Math.min(fields.receiverRow,lastRow);
  cell('X',receiverColumns[0],receiverColumns[1],receiverRows[selectedRow],receiverRows[selectedRow+1],normal,10,'center');
  cell(fields.deliveryNumber,receiverColumns[5],receiverColumns[6],receiverRows[selectedRow],receiverRows[selectedRow+1],normal,8,'center');

  for (const entry of fields.waste) {
    const values = ['X',entry.packages,entry.packaging,entry.estimatedKg && `${entry.estimatedKg} kg`,
      entry.weighedKg,entry.adrLabel,entry.adr === 'none' ? 'X' : ''];
    values.forEach((value,i) => cell(value,wasteColumns[i],wasteColumns[i+1],wasteRows[entry.row],wasteRows[entry.row+1],bold,8,'center'));
  }

  function sign({date,name,strokes}: Signoff, top: number, bottom: number) {
    cell(date,177.3,248.1,top,bottom,bold,10);
    cell(name,403.8,559.3,top,bottom,bold,8,'left',true);
    for (const stroke of strokes) {
      const points = stroke.map(([x,y]) => ({x:252 + x * 147,y:height - top - 2 - y * (bottom - top - 4)}));
      points.forEach((end,index) => {
        if (index) page.drawLine({start:points[index-1],end,thickness:0.85,color:rgb(0.12,0.17,0.36)});
        else page.drawCircle({x:end.x,y:end.y,size:0.42,color:rgb(0.12,0.17,0.36)});
      });
    }
  }
  sign(fields.senderSignoff,707.95,736.05);
  sign(fields.receiverSignoff,736.05,770.25);
  return pdf.save();
}
