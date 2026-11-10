import {PDFDocument,StandardFonts,rgb,type PDFPage}from'pdf-lib';
import {elleholmsLogoJpeg}from'./internal-economy-logo';
export type EconomyRow={source_key:string;row_id:string;occurred_on:string;order:string;order_status:string;littra:string;project:string;vehicle:string;driver:string;article:string;description:string;quantity:number|null;unit:string;rate:number|null;amount:number|null;original_amount:number;debit_amount:number|null;discount_amount:number|null;category:string;price_status:string;price_basis:string;estimated:boolean;preliminary:boolean;from_center:string;to_center:string;component:string;review_reason:string};
type EconomyTotal={rows:number;missing_rows:number;total:number|null;priced_amount:number;debit_amount:number|null;discount_amount:number;material:number|null;transport:number;tipp_deponi:number};
export type InternalEconomyReport={version:number;period:{from:string;to:string};created_at:string;generation:string|null;rows:EconomyRow[];totals:EconomyTotal&{estimated_rows:number;preliminary_rows:number};centers:Array<EconomyTotal&{center:string}>;projects:Array<EconomyTotal&{center:string;project:string;name:string}>;reconciliation:{conflictCount:number;unassignedRows:number;otherRows:number;invalidAmountRows:number};basis:string};
const black=rgb(.08,.09,.1),muted=rgb(.35,.38,.4),line=rgb(.78,.8,.81),yellow=rgb(1,.82,.05);
const clean=(v:unknown)=>String(v??'').replace(/[\u0000-\u001f]/g,' ').replace(/[\u2010-\u2015\u2212]/g,'-').replace(/[^\u0020-\u007e\u00a0-\u00ff\u20ac]/g,' ');
const number=(v:number|null|undefined,digits=2)=>v==null?'SAKNAS':new Intl.NumberFormat('sv-SE',{minimumFractionDigits:digits,maximumFractionDigits:digits}).format(v);
export async function internalEconomyPdf(report:InternalEconomyReport, options?:{title:string; workshop:boolean; note:string}){
 const pdf=await PDFDocument.create(),font=await pdf.embedFont(StandardFonts.Helvetica),bold=await pdf.embedFont(StandardFonts.HelveticaBold),logo=await pdf.embedJpg('data:image/jpeg;base64,'+elleholmsLogoJpeg);
 const pages:PDFPage[]=[];let page!:PDFPage;let y=0;const left=24,width=794;
 const text=(v:unknown,x:number,yy:number,size=8,strong=false,color=black)=>page.drawText(clean(v),{x,y:yy,size,font:strong?bold:font,color});
 function rightText(v:unknown,right:number,yy:number,size:number,strong=false,color=black,maxWidth=Infinity){const value=clean(v),face=strong?bold:font, measured=face.widthOfTextAtSize(value,size);const fitted=measured>maxWidth?size*maxWidth/measured:size;text(value,right-face.widthOfTextAtSize(value,fitted),yy,fitted,strong,color);}
 function wrap(v:unknown,w:number,size=7){const words=clean(v).split(/\s+/),lines:string[]=[];let part='';for(const word of words){if(font.widthOfTextAtSize(part?part+' '+word:word,size)>w&&part){lines.push(part);part='';}let rest=word;while(font.widthOfTextAtSize(rest,size)>w){let n=rest.length-1;while(n>1&&font.widthOfTextAtSize(rest.slice(0,n),size)>w)n--;if(part){lines.push(part);part='';}lines.push(rest.slice(0,n));rest=rest.slice(n);}part=part?part+' '+rest:rest;}if(part)lines.push(part);return lines.length?lines:[''];}
 function newPage(title:string){page=pdf.addPage([842,595]);pages.push(page);page.drawImage(logo,{x:left,y:537,width:173,height:47});text('Internöverföring - underlag till ekonomi',230,565,15,true);text(title,230,546,10,true);text(`${report.period.from} - ${report.period.to} | Belopp i SEK, exklusive moms`,230,530,8,false,muted);page.drawRectangle({x:left,y:516,width,height:3,color:yellow});y=499;}
 const {rows,centers,projects}=report;
 const title=options?.title??'Internöverföringar';
 const workshop=options?.workshop??false;
 newPage(title);
 for(const c of centers){
  text(c.center==='30'?'30 Transport':workshop?'40 Verkstaden':'20 Sortergården',left,y,10,true);
  const summary:Array<[string,number|null,boolean]>=[
   ['Summa att överföra',c.total,true],
   ['Debiterbart belopp',c.debit_amount,false],
   ['Mellanskillnad',c.total===null||c.debit_amount===null?null:Math.round((c.debit_amount-c.total)*100)/100,false],
  ];
  for(const[label,value,strong]of summary){text(label,285,y,9,strong);text(value===null?'–':number(value)+' kr',440,y,strong?13:11,strong);y-=22;}
  if(c.missing_rows){text(`Ofullständigt underlag: ${c.missing_rows} rader saknar pris. Prissatt del: ${number(c.priced_amount)} kr.`,left,y,8,false,muted);y-=18;}
  if(options?.note){text(options.note,left,y,8,false,muted);y-=16;}
  y-=10;
 }
 const projectAmounts=[['Transport',550],['Material',680],[workshop?'Verkstad':'Tipp',745],['Summa',814]]as const;
 const projectHeader=()=>{page.drawRectangle({x:left,y:y-5,width,height:18,color:black});const white=rgb(1,1,1);text('KST',left+4,y,8,true,white);text('Projekt / littra',left+40,y,8,true,white);for(const [label,right]of projectAmounts)rightText(label,right,y,8,true,white);y-=23;};
 text('Sammanställning per projekt / littra',left,y,10,true);y-=22;projectHeader();
 for(const p of projects){const names=wrap(p.name||p.project||'Projekt saknas',420,7.5),h=Math.max(18,names.length*9+6);if(y-h<45){newPage(title+' - projektsammanställning');projectHeader();}text(p.center,left+4,y,7.5);names.forEach((l,i)=>text(l,left+40,y-i*9,7.5));[p.transport,p.material,p.tipp_deponi,p.total].forEach((v,i)=>rightText(number(v),projectAmounts[i][1],y,7));page.drawLine({start:{x:left,y:y-h+7},end:{x:left+width,y:y-h+7},thickness:.3,color:line});y-=h;}
 const columns=[['Order',30],['Projekt / littra',120],['RegNr',44],['Förare',60],['Datum',48],['Artikel',35],['Artikelnamn',150],['Mängd',32],['Enhet',22],['Debiterat',62],['Prisgrund',54],['À-pris',54],['Överförs',68]]as const;
 const numericColumns=new Set([7,9,11,12]);
 function detailsHeader(){let x=left;page.drawRectangle({x:left,y:y-5,width,height:18,color:black});const white=rgb(1,1,1);columns.forEach(([label,w],i)=>{if(numericColumns.has(i))rightText(label,x+w-3,y,7,true,white);else text(label,x+3,y,7,true,white);x+=w;});y-=23;}
 if(rows.length){newPage(title+' - orderrader');detailsHeader();
  for(const r of rows){
   const status=({Invoiced:'Fakt.',ReadyForInvoicing:'Redo',Reported:'Rapp.'}as Record<string,string>)[r.order_status]??r.order_status;
   const cells=[[r.order,status].filter(Boolean).join(' '),r.littra||r.project,r.vehicle,r.driver,r.occurred_on,r.article,r.description,r.quantity==null?'':number(r.quantity),r.unit,r.debit_amount==null?'':number(r.debit_amount),workshop?'Next 4630':!r.price_status?'Workify':r.category==='material'&&r.price_status!=='internal_price_full'?'Självkost':'Fullt pris',r.rate==null?'':number(r.rate),number(r.amount)];
   const wrapped=cells.map((v,i)=>numericColumns.has(i)?[v]:wrap(v,columns[i][1]-6,6.5)),h=Math.max(17,...wrapped.map(a=>a.length*8+6));
   if(y-h<45){newPage(title+' - orderrader (forts.)');detailsHeader();}
   let x=left;wrapped.forEach((lines,i)=>{const w=columns[i][1];lines.forEach((v,j)=>{if(numericColumns.has(i))rightText(v,x+w-3,y-j*8,6.5,i===12,black,w-6);else text(v,x+3,y-j*8,6.5);});x+=w;});
   if(r.preliminary)page.drawRectangle({x:left-6,y:y-2,width:3,height:8,color:yellow});
   page.drawLine({start:{x:left,y:y-h+6},end:{x:left+width,y:y-h+6},thickness:.25,color:line});y-=h;
  }
 }
 for(const p of pages){page=p;text(`Elleholms Maskin AB | Skapad ${report.created_at.slice(0,10)} | Underlag - ingen automatisk bokföring`,left,22,7,false,muted);}
 pdf.setTitle('Internöverföring - underlag till ekonomi');pdf.setAuthor('Elleholms Maskin AB');return pdf.save();
}
