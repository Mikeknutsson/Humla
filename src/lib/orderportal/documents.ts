import {PDFDocument, StandardFonts, rgb, type PDFFont, type PDFPage} from 'pdf-lib';
import type {DocumentSettings} from './customer-card';
import type {Order} from './model';

export type OrderDocument = 'delivery-note'|'invoice-basis';
const ink=rgb(.12,.14,.16);
const yellow=rgb(.95,.77,0);
const gray=rgb(.94,.95,.96);
const number=new Intl.NumberFormat('sv-SE',{maximumFractionDigits:4});
const money=new Intl.NumberFormat('sv-SE',{minimumFractionDigits:2,maximumFractionDigits:2});
const width=595.28;
const height=841.89;
const margin=42;
const content=width-margin*2;

function wrap(text:string,font:PDFFont,size:number,available:number){
 const safe=Array.from(text.normalize('NFC').replaceAll('→',' till '),character=>{
  if(character==='\n')return character;
  if(character==='\t')return ' ';
  try{font.encodeText(character);return character;}catch{return '?';}
 }).join('');
 return safe.split('\n').flatMap(paragraph=>{
  const lines:string[]=[];
  let line='';
  for(const word of paragraph.split(/\s+/)){
   const next=line?line+' '+word:word;
   if(font.widthOfTextAtSize(next,size)<=available){line=next;continue;}
   if(line)lines.push(line);
   line='';
   for(const character of word){
    if(font.widthOfTextAtSize(line+character,size)>available){lines.push(line);line='';}
    line+=character;
   }
  }
  lines.push(line);
  return lines;
 });
}

export async function orderDocumentPdf(order:Order,kind:OrderDocument,settings:DocumentSettings){
 const pdf=await PDFDocument.create();
 const regular=await pdf.embedFont(StandardFonts.Helvetica);
 const bold=await pdf.embedFont(StandardFonts.HelveticaBold);
 const invoice=kind==='invoice-basis';
 const heading=invoice?'Fakturaunderlag':'Följesedel';
 pdf.setTitle(heading+' '+order.number);
 let page!:PDFPage;
 let y=0;
 function draw(text:string,x:number,at:number,size:number,font=regular,color=ink){
  page.drawText(text,{x,y:at,size,font,color});
 }
 function newPage(){
  page=pdf.addPage([width,height]);
  page.drawRectangle({x:0,y:height-100,width,height:100,color:ink});
  page.drawRectangle({x:0,y:height-104,width,height:4,color:yellow});
  draw('HUMLA  /  ORDER & TRANSPORT',margin,height-33,10,bold,yellow);
  draw(heading,margin,height-68,25,bold,rgb(1,1,1));
  draw('TESTUNDERLAG',width-margin-94,height-68,10,bold,yellow);
  y=height-130;
 }
 function reserve(space:number){
  if(y-space<58)newPage();
 }
 function paragraph(value:string,size=11,font=regular){
  for(const line of wrap(value,font,size,content)){
   reserve(16);draw(line,margin,y,size,font);y-=16;
  }
 }
 function field(label:string,value:string|undefined){
  if(!value)return;
  reserve(34);paragraph(label,9,bold);paragraph(value);y-=5;
 }
 newPage();
 paragraph('Order '+order.number+'  /  Version '+order.version+'  /  '+order.status,10,bold);
 y-=12;
 field('Kund',order.customer);
 field('Uppdrag',order.title);
 field('Projekt',order.project);
 field('Märkning',order.marking);
 field('Vår referens',order.reference);
 field('Planerad tid',[order.start,order.end].filter(Boolean).map(value=>value.replace('T',' ')).join(' till '));
 field('Fordon',order.vehicle);
 if(settings.showRoute)field('Hämt- och lämnaplats',order.location);
 reserve(44);y-=8;paragraph('Orderrader',15,bold);
 if(!order.lines.length)paragraph('Inga orderrader.');
 for(const [index,line] of order.lines.entries()){
  reserve(56);
  page.drawRectangle({x:margin,y:y-8,width:content,height:25,color:gray});
  draw('Rad '+(index+1),margin+8,y,10,bold);
  y-=25;
  paragraph([line.article,line.label].filter(Boolean).join(' / '),11,bold);
  paragraph([line.date,number.format(line.quantity)+' '+line.unit].filter(Boolean).join('  |  '));
  if(invoice)paragraph('À-pris '+money.format(line.price)+' kr  |  Radbelopp '+money.format(line.amount)+' kr');
  y-=9;
 }
 if(invoice){reserve(38);y-=8;paragraph('Totalt exkl. moms  '+money.format(order.amount)+' kr',14,bold);}
 if(!invoice&&settings.signature){
  reserve(78);y-=18;paragraph('Mottagarens underskrift',11,bold);
  y-=24;
  page.drawLine({start:{x:margin,y},end:{x:margin+260,y},thickness:.7,color:ink});
  y-=14;draw('Namn och datum',margin,y,9);
 }
 const pages=pdf.getPages();
 pages.forEach((sheet,i)=>{
  sheet.drawLine({start:{x:margin,y:44},end:{x:width-margin,y:44},thickness:.6,color:ink});
  sheet.drawText('TESTUNDERLAG  /  Skapat i Humlas orderportal', {x:margin,y:29,size:8,font:regular,color:ink});
  sheet.drawText(`${i+1} / ${pages.length}`,{x:width-margin-30,y:29,size:8,font:regular,color:ink});
 });
 return pdf.save();
}
