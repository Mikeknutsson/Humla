import * as XLSX from 'xlsx';

const columns = {
  code:'kod', name:'benämning', unit:'enhet', account:'kontonr', price_list:'prislista pris/enh',
  price:'pris/enh', cost:'kostn/enh', performed:'utförd datum',
  project:'projektnr', project_name:'projektnamn', work_order:'ao nr', order_name:'ao/äta-benämning',
  center:'kostnadsställe', quantity:'utf mängd', value:'utf intäkt', actual_cost:'utf kostnad',
  invoiced:'fakturerat', billable:'debiterbar', invoice_number:'faktura nr',

} as const;

type Article = {
  code:string; name:string; unit:string; account:string; price_list:string;
  min_price:number|null; max_price:number|null; min_cost:number|null; max_cost:number|null;
  source_rows:number; last_performed_on:string|null;
};

type WorkshopResourceRow={
  sheet:string; source_row:number; project:string; project_name:string; work_order:string; order_name:string;
  center:string; code:string; article:string; unit:string; performed_on:string|null; quantity:number|null;
  value:number|null; actual_cost:number|null; invoiced:boolean|null; billable:boolean|null; invoice_number:string;
};

function readFlag(value:unknown) {
  if(typeof value==='boolean')return value;
  const flag=String(value??'').trim().toLocaleLowerCase('sv');
  if(['true','1','ja','sant'].includes(flag))return true;
  if(['false','0','nej','falskt'].includes(flag))return false;
  return null;
}

function readAmount(value:unknown) {
  if (typeof value === 'number') return Number.isFinite(value) && Math.abs(value)<1e12 ? value : null;
  const text=String(value??'').trim().replace(/\s/g,'').replace(/(?:SEK|kr)$/i,'');
  if(!/^[+-]?\d+(?:[,.]\d+)?$/.test(text))return null;
  const amount=Number(text.replace(',','.'));
  return Math.abs(amount)<1e12?amount:null;
}

function readDate(value:unknown) {
  const date=typeof value==='number'?XLSX.SSF.parse_date_code(value):null;
  const text=date?`${String(date.y).padStart(4,'0')}-${String(date.m).padStart(2,'0')}-${String(date.d).padStart(2,'0')}`:String(value??'').trim();
  if(!/^\d{4}-\d{2}-\d{2}$/.test(text))return null;
  const time=Date.parse(text);
  return Number.isFinite(time)&&new Date(time).toISOString().slice(0,10)===text?text:null;
}

function priceRange(min:number|null,max:number|null,value:number|null):[number|null,number|null] {
  return value===null?[min,max]:[min===null?value:Math.min(min,value),max===null?value:Math.max(max,value)];
}

export function isNextArticleResourceExport(headers:unknown[]) {
  const labels=new Set(headers.map(value=>String(value??'').trim().toLocaleLowerCase('sv')));
  return ['ao nr',columns.code,columns.name,columns.unit].every(label=>labels.has(label));
}

export function readNextArticleFile(bytes:Uint8Array,{includeWorkshop=false}={}) {
  if(!((bytes[0]===0x50&&bytes[1]===0x4b)||(bytes[0]===0xd0&&bytes[1]===0xcf)))throw Error('Välj originalexporten i Excel-format.');
  const workbook=XLSX.read(bytes,{type:'array'});
  const articles=new Map<string,Article>();
  const skipped:string[]=[];
  const workshopRows:WorkshopResourceRow[]=[];
  let workshopColumns=false;
  let matched=false, sourceRows=0, periodStart:string|null=null, periodEnd:string|null=null;
  for(const sheetName of workbook.SheetNames) {
    const sheet=workbook.Sheets[sheetName];
    if(!sheet['!ref'])continue;
    const range=XLSX.utils.decode_range(sheet['!ref']);
    if(range.e.c-range.s.c>200)throw Error('Excelbladet har för många kolumner. Exportera resursuppföljningen på nytt.');
    const header=XLSX.utils.sheet_to_json<string[]>(sheet,{header:1,raw:false,range:{s:range.s,e:{r:range.s.r,c:range.e.c}}})[0];
    if(!header)continue;
    const labels=header.map(value=>String(value??'').trim().toLocaleLowerCase('sv'));
    const indexes=Object.fromEntries(Object.entries(columns).map(([key,label])=>[key,labels.indexOf(label)]));
    if(!isNextArticleResourceExport(header))continue;
    matched=true;
    const canReadWorkshop=indexes.account>=0&&indexes.value>=0&&indexes.performed>=0;
    workshopColumns ||= canReadWorkshop;
    if(range.e.r-range.s.r>30000)throw Error('Exporten har fler än 30 000 rader. Exportera en kortare period.');
    for(let r=range.s.r+1;r<=range.e.r;r++) {
      const cell=(key:keyof typeof columns)=>indexes[key]<0?undefined:sheet[XLSX.utils.encode_cell({r,c:range.s.c+indexes[key]})];
      const label=(key:keyof typeof columns)=>String(cell(key)?.w??cell(key)?.v??'').trim();
      const code=label('code'), name=label('name'), unit=label('unit').toLocaleLowerCase('sv');
      const account=label('account'), price_list=label('price_list');
      if(!code&&!name&&!unit&&!account&&!price_list&&!cell('performed')?.v&&!cell('price')?.v&&!cell('cost')?.v)continue;
      if(++sourceRows>30000)throw Error('Exporten har fler än 30 000 rader. Exportera en kortare period.');
      const performed=readDate(cell('performed')?.v);
      if(includeWorkshop&&canReadWorkshop&&account==='4630')workshopRows.push({
        sheet:sheetName,source_row:r+1,project:label('project'),project_name:label('project_name'),
        work_order:label('work_order'),order_name:label('order_name'),center:label('center'),
        code,article:name,unit,performed_on:performed,quantity:readAmount(cell('quantity')?.v),
        value:readAmount(cell('value')?.v),actual_cost:readAmount(cell('actual_cost')?.v),
        invoiced:readFlag(cell('invoiced')?.v),billable:readFlag(cell('billable')?.v),invoice_number:label('invoice_number'),
      });
      if(!code||!name||code.length>100||name.length>250||unit.length>50||account.length>50||price_list.length>200) {
        skipped.push(`${sheetName}, rad ${r+1}`);
        continue;
      }
      if(performed) {
        if(periodStart===null||performed<periodStart)periodStart=performed;
        if(periodEnd===null||performed>periodEnd)periodEnd=performed;
      }
      const key=JSON.stringify([code,name,unit,account,price_list]);
      const article=articles.get(key)??{code,name,unit,account,price_list,min_price:null,max_price:null,min_cost:null,max_cost:null,source_rows:0,last_performed_on:null};
      [article.min_price,article.max_price]=priceRange(article.min_price,article.max_price,readAmount(cell('price')?.v));
      [article.min_cost,article.max_cost]=priceRange(article.min_cost,article.max_cost,readAmount(cell('cost')?.v));
      article.source_rows++;
      if(performed&&(article.last_performed_on===null||performed>article.last_performed_on))article.last_performed_on=performed;
      articles.set(key,article);
    }
  }
  if(!matched)throw Error('Inget blad för Arbetsorder – Resursuppföljning hittades. Exporten behöver innehålla AO nr, Kod, Benämning och Enhet.');
  if(!articles.size)throw Error('Inga giltiga rader med artikelkod och benämning hittades.');
  if(articles.size>10000)throw Error('Exporten har fler än 10 000 artikelvarianter. Exportera en kortare period.');
  return {articles:[...articles.values()],sourceRows,skipped,periodStart,periodEnd,workshopRows,workshopColumns};
}

export function nextArticleImportSummary({articles,sourceRows,skipped,periodStart,periodEnd}:ReturnType<typeof readNextArticleFile>) {
  return {rows:articles.length,sourceRows,skipped:skipped.length,skippedExamples:skipped.slice(0,5),periodStart,periodEnd};
}

export function nextArticleImportPreview(parsed:ReturnType<typeof readNextArticleFile>) {
  return {...nextArticleImportSummary(parsed),preview:parsed.articles.slice(0,8)};
}

export type NextArticlePreview=ReturnType<typeof nextArticleImportPreview>;
