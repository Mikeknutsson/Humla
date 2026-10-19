import {PDFDocument,StandardFonts,rgb,type PDFPage}from'pdf-lib';
import {elleholmsLogoJpeg}from'./internal-economy-logo';
export type EconomyRow={source_key:string;row_id:string;occurred_on:string;order:string;order_status:string;littra:string;project:string;vehicle:string;driver:string;article:string;description:string;quantity:number|null;unit:string;rate:number|null;amount:number|null;original_amount:number;debit_amount:number|null;discount_amount:number|null;category:string;price_status:string;price_basis:string;estimated:boolean;preliminary:boolean;from_center:string;to_center:string;component:string;review_reason:string};
type EconomyTotal={rows:number;missing_rows:number;total:number|null;priced_amount:number;debit_amount:number;discount_amount:number;material:number;transport:number;tipp_deponi:number};
export type InternalEconomyReport={version:number;period:{from:string;to:string};created_at:string;generation:string|null;rows:EconomyRow[];totals:EconomyTotal&{estimated_rows:number;preliminary_rows:number};centers:Array<EconomyTotal&{center:string}>;projects:Array<EconomyTotal&{center:string;project:string;name:string}>;reconciliation:{conflictCount:number;unassignedRows:number;otherRows:number;invalidAmountRows:number};basis:string};
const black=rgb(.08,.09,.1),muted=rgb(.35,.38,.4),line=rgb(.78,.8,.81),yellow=rgb(1,.82,.05);
const clean=(v:unknown)=>String(v??'').replace(/[\u0000-\u001f]/g,' ').replace(/[\u2010-\u2015]/g,'-').replace(/[^\u0020-\u007e\u00a0-\u00ff\u20ac]/g,' ');
const number=(v:number|null|undefined,digits=2)=>v==null?'SAKNAS':new Intl.NumberFormat('sv-SE',{minimumFractionDigits:digits,maximumFractionDigits:digits}).format(v);
export async function internalEconomyPdf(report:InternalEconomyReport,center?:string){
 const pdf=await PDFDocument.create(),font=await pdf.embedFont(StandardFonts.Helvetica),bold=await pdf.embedFont(StandardFonts.HelveticaBold),logo=await pdf.embedJpg('data:image/jpeg;base64,'+elleholmsLogoJpeg);
 const pages:PDFPage[]=[];let page!:PDFPage;let y=0;const left=24,width=794;
 const text=(v:unknown,x:number,yy:number,size=8,strong=false,color=black)=>page.drawText(clean(v),{x,y:yy,size,font:strong?bold:font,color});
 function wrap(v:unknown,w:number,size=7){const words=clean(v).split(/\s+/),lines:string[]=[];let part='';for(const word of words){if(font.widthOfTextAtSize(part?part+' '+word:word,size)>w&&part){lines.push(part);part='';}let rest=word;while(font.widthOfTextAtSize(rest,size)>w){let n=rest.length-1;while(n>1&&font.widthOfTextAtSize(rest.slice(0,n),size)>w)n--;if(part){lines.push(part);part='';}lines.push(rest.slice(0,n));rest=rest.slice(n);}part=part?part+' '+rest:rest;}if(part)lines.push(part);return lines.length?lines:[''];}
 function newPage(title:string){page=pdf.addPage([842,595]);pages.push(page);page.drawImage(logo,{x:left,y:537,width:173,height:47});text('Internöverföring - underlag till ekonomi',230,565,15,true);text(title,230,546,10,true);text(`${report.period.from} - ${report.period.to} | Belopp i SEK, exklusive moms`,230,530,8,false,muted);page.drawRectangle({x:left,y:516,width,height:3,color:yellow});y=499;}
 function paragraph(value:string){for(const l of wrap(value,width,8)){text(l,left,y,8,false,muted);y-=11;}y-=7;}
 const rows=report.rows.filter(r=>!center||r.to_center===center),centers=report.centers.filter(c=>!center||c.center===center),projects=report.projects.filter(p=>!center||p.center===center);
 const title=center?`Överföring till ${center} ${center==='30'?'Transport':'Sortergården'} från 10 Entreprenad`:'Överföring från 10 Entreprenad till Transport och Sortergården';
 newPage(title);
 for(const c of centers){const label=c.center==='30'?'30 Transport':'20 Sortergården';text(label,left,y,10,true);text(c.missing_rows?'Prissatt del':'Summa att överföra',285,y,9);text(number(c.total??c.priced_amount)+' kr',440,y,13,true);y-=22;}
 paragraph('Material redovisas till självkostnad utan materialpåslag. Transport och tipp/deponi: fullt debiteringspris. En gul markering vid raden anger uppskattat pris eller preliminär koppling.');
 paragraph(`Debiterat belopp före materialjustering: ${number(centers.reduce((s,c)=>s+c.debit_amount,0))} kr. Materialpåslaget ersätts med självkostnadspriset.`);
 const missing=rows.filter(r=>r.amount===null).length,estimated=rows.filter(r=>r.estimated).length;
 paragraph(`${rows.length} rapportrader. ${estimated} materialrader har uppskattat självkostnadspris. ${missing?`${missing} rader saknar pris eller uppdelning: totalsumman är ofullständig. Dessa står kvar i detaljlistan med SAKNAS.`:'Samtliga rapportrader har belopp.'}`);
 if(report.reconciliation.conflictCount||report.reconciliation.unassignedRows||report.reconciliation.otherRows||report.reconciliation.invalidAmountRows)paragraph(`Avstämning för hela periodens internunderlag: ${report.reconciliation.conflictCount} motstridiga källnycklar, ${report.reconciliation.unassignedRows} rader utan intäkts-KST, ${report.reconciliation.otherRows} rader på andra överföringar och ${report.reconciliation.invalidAmountRows} rader utan läsbart belopp. Dessa ingår inte i denna filens KST 10 -> 20/30-summa. Se avstämningen i Humla.`);
 const projectHeader=()=>{page.drawRectangle({x:left,y:y-5,width,height:18,color:black});text('KST',left+4,y,8,true,rgb(1,1,1));text('Projekt / littra',left+40,y,8,true,rgb(1,1,1));text('Transport',480,y,8,true,rgb(1,1,1));text('Material - självkostnad',555,y,8,true,rgb(1,1,1));text('Tipp',685,y,8,true,rgb(1,1,1));text('Summa',750,y,8,true,rgb(1,1,1));y-=23;};
 text('Sammanställning per mottagande projekt',left,y,10,true);y-=22;projectHeader();
 for(const p of projects){const names=wrap(p.name||p.project||'Projekt saknas',420,7.5),h=Math.max(18,names.length*9+6);if(y-h<45){newPage(title+' - projektsammanställning');projectHeader();}text(p.center,left+4,y,7.5);names.forEach((l,i)=>text(l,left+40,y-i*9,7.5));[p.transport,p.material,p.tipp_deponi,p.total].forEach((v,i)=>{const x=[480,555,685,750][i],w=[70,125,60,64][i],s=clean(number(v));text(s,x+w-font.widthOfTextAtSize(s,7),y,7);});page.drawLine({start:{x:left,y:y-h+7},end:{x:left+width,y:y-h+7},thickness:.3,color:line});y-=h;}
 const columns=[['Order',30],['Projekt / littra',120],['RegNr',44],['Förare',60],['Datum',48],['Artikel',35],['Artikelnamn',150],['Mängd',32],['Enhet',22],['Debiterat',62],['Prisgrund',54],['À-pris',54],['Överförs',68]]as const;
 function detailsHeader(){let x=left;page.drawRectangle({x:left,y:y-5,width,height:18,color:black});for(const[label,w]of columns){text(label,x+3,y,7,true,rgb(1,1,1));x+=w;}y-=23;}
 for(const c of centers){newPage(`Till ${c.center} ${c.center==='30'?'Transport':'Sortergården'} från 10 Entreprenad - orderrader`);detailsHeader();
  for(const r of rows.filter(r=>r.to_center===c.center)){
   const status=({Invoiced:'Fakt.',ReadyForInvoicing:'Redo',Reported:'Rapp.'}as Record<string,string>)[r.order_status]??r.order_status;
   const cells=[r.order+' '+status,r.littra||r.project,r.vehicle,r.driver,r.occurred_on,r.article,r.description,number(r.quantity),r.unit,number(r.debit_amount),r.category==='material'?'Självkost':'Fullt pris',number(r.rate),number(r.amount)];
   const wrapped=cells.map((v,i)=>wrap(v,columns[i][1]-6,6.5)),h=Math.max(17,...wrapped.map(a=>a.length*8+6));
   if(y-h<45){newPage(`Till ${c.center} från 10 Entreprenad - orderrader (forts.)`);detailsHeader();}
   let x=left;wrapped.forEach((lines,i)=>{lines.forEach((v,j)=>{const right=i>=7&&i!==8;const xx=right?x+columns[i][1]-3-font.widthOfTextAtSize(v,6.5):x+3;text(v,xx,y-j*8,6.5,i===12);});x+=columns[i][1];});
   if(r.preliminary)page.drawRectangle({x:left-6,y:y-2,width:3,height:8,color:yellow});
   page.drawLine({start:{x:left,y:y-h+6},end:{x:left+width,y:y-h+6},thickness:.25,color:line});y-=h;
  }
 }
 const evidence=rows.filter(r=>r.category==='material'||r.amount===null);
 if(evidence.length){newPage('Prisunderlag - materialets självkostnad');paragraph('Stjärna (*) = uppskattat självkostnadspris enligt godkänd Hub-regel. Materialradernas pris är ett inköps-/självkostnadsunderlag, inte ett internt försäljningspris.');
  for(const r of evidence){const notes=wrap(`${r.order} | ${r.occurred_on} | ${r.article} | ${r.littra||r.project} | ${number(r.rate)} kr/${r.unit} | ${r.estimated?'* Uppskattat pris':r.price_status} | ${r.price_basis||r.review_reason||'Pris/uppdelning saknas'}`,width-8,8),h=notes.length*11+12;if(y-h<45)newPage('Prisunderlag (forts.)');notes.forEach((l,i)=>text(l,left+4,y-i*11,8));y-=h;}
 }
 for(const[p,i]of pages.map((p,i)=>[p,i]as const)){page=p;text(`Elleholms Maskin AB | Skapad ${report.created_at.slice(0,10)} | Underlag - ingen automatisk bokföring`,left,22,7,false,muted);text(`Sida ${i+1} / ${pages.length}`,748,22,7,false,muted);}
 pdf.setTitle('Internöverföring - material till självkostnad');pdf.setAuthor('Elleholms Maskin AB');return pdf.save();
}
