import * as XLSX from 'xlsx/xlsx.mjs';
export type StenaMapping=Record<string,string>;
export type StenaRow={row_number:number;booking:string;date:string;registration:string;price:number|null;extra:number|null;load_count:number|null;settled_amount:number|null;load_carrier_type:string};
export function stenaNumber(value:unknown):number|null{
 if(value==null||String(value).trim()==='')return null;
 const n=typeof value==='number'?value:Number(String(value).replace(/[\s\u00a0]/g,'').replace(',','.'));
 if(!Number.isFinite(n))throw Error('Ogiltigt tal: '+String(value));return n;
}
function date(value:unknown):string{
 let text=String(value??'').trim();
 if(typeof value==='number'){const d=XLSX.SSF.parse_date_code(value);if(!d)throw Error('Ogiltigt datum');text=`${d.y}-${String(d.m).padStart(2,'0')}-${String(d.d).padStart(2,'0')}`;}
 text=text.slice(0,10).replace(/\//g,'-');
 if(!/^\d{4}-\d{2}-\d{2}$/.test(text)||!Number.isFinite(Date.parse(text))||new Date(text+'T00:00:00Z').toISOString().slice(0,10)!==text)throw Error('Ogiltigt datum: '+text);return text;
}
export function stenaWorkbook(bytes:Uint8Array,sheet?:string,header=1){
 const book=XLSX.read(bytes,{type:'array',cellDates:false});const name=sheet||book.SheetNames[0];
 if(!name||!book.Sheets[name])throw Error('Kalkylblad saknas');
 if(!Number.isInteger(header)||header<1||header>50)throw Error('Rubrikrad måste vara 1–50');
 const matrix=XLSX.utils.sheet_to_json<unknown[]>(book.Sheets[name],{header:1,defval:'',raw:true});
 const headers=(matrix[header-1]??[]).map((v,i)=>({key:String(i),label:`${XLSX.utils.encode_col(i)} – ${String(v||'Utan rubrik')}`}));
 const rows=matrix.slice(header).map((values,i)=>({values,row_number:header+i+1})).filter(r=>r.values.some(v=>String(v).trim()));
 if(rows.length>20000)throw Error('Max 20 000 rader per fil');if(!rows.length)throw Error('Filen saknar datarader');
 return {sheets:book.SheetNames,sheet:name,headers,rows};
}
export function normalizeStena(table:ReturnType<typeof stenaWorkbook>,mapping:StenaMapping,kind:string):StenaRow[]{
 if(!['history','settled'].includes(kind))throw Error('Välj Historik eller Avräknade transporter');
 for(const k of ['booking','date',...(kind==='settled'?['settled_amount']:['price'])])if(mapping[k]==null||mapping[k]==='')throw Error('Kolumn saknas: '+k);
 const bookings=new Set<string>();
 return table.rows.map(({values,row_number})=>{
  const get=(key:string)=>{const index=mapping[key];if(index==null||index==='')return '';if(!/^\d+$/.test(index)||Number(index)>=table.headers.length)throw Error('Ogiltigt kolumnval');return values[Number(index)]??'';};
  try{
   const booking=String(get('booking')).trim();if(!/^\d{8}$/.test(booking))throw Error('Bokningsnummer ska ha 8 siffror');
   if(bookings.has(booking))throw Error('Bokningsnummer förekommer flera gånger i filen');bookings.add(booking);
   const count=stenaNumber(get('load_count'));if(count!=null&&count<0)throw Error('Antal får inte vara negativt');
   return {row_number,booking,date:date(get('date')),registration:String(get('registration')).trim(),price:stenaNumber(get('price')),extra:stenaNumber(get('extra')),load_count:count,settled_amount:stenaNumber(get('settled_amount')),load_carrier_type:String(get('load_carrier_type')).trim()};
  }catch(e){throw Error(`Rad ${row_number}: ${e instanceof Error?e.message:'Ogiltig rad'}`);}
 });
}
