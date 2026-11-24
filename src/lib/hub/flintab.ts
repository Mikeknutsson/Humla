import * as XLSX from 'xlsx';

export const flintabHeaders = ['TransId','Datum','Lastbärare','Avsändare (Id)','Mottagare (Id)','Referens','Ordernr','Artikel (Id)','Vikt','Lagerplats','Leveranstyp'];
type Cell = string | number | boolean | null;
const str = (value: Cell | undefined) => String(value ?? '').trim();

function date(value: Cell) {
  let parts: number[];
  if (typeof value === 'number') {
    const parsed = XLSX.SSF.parse_date_code(value);
    if (!parsed) return '';
    parts = [parsed.y,parsed.m,parsed.d];
  } else {
    const match = str(value).match(/^(\d{2}|\d{4})-(\d{2})-(\d{2})(?:\s+\d{2}:\d{2}(?::\d{2})?)?$/);
    if (!match) return '';
    parts = match.slice(1).map(Number);
    if (match[1].length === 2) parts[0] += 2000;
  }
  const [year,month,day] = parts;
  const normalized = parts.map((part,i)=>String(part).padStart(i ? 2 : 4,'0')).join('-');
  const parsed = new Date(Date.UTC(year,month-1,day));
  return year >= 2000 && year <= 2100 && parsed.toISOString().slice(0,10) === normalized ? normalized : '';
}

export function parseFlintab(bytes: Uint8Array) {
  const book = XLSX.read(bytes,{type:'array',sheetRows:20004});
  for (const sheet of book.SheetNames) {
    const cells = XLSX.utils.sheet_to_json<Cell[]>(book.Sheets[sheet],{header:1,defval:null,blankrows:true});
    const header = cells.slice(0,40).findIndex(row => flintabHeaders.every(label => row.some(value => str(value) === label)));
    if (header < 0) continue;
    if (cells.length >= 20004) throw Error('Filen har för många rader. Exportera ett kortare intervall.');
    const columns = flintabHeaders.map(label => cells[header].findIndex(value=>str(value)===label));
    const seen = new Set<string>();
    const rows: {id: string; date: string; kg: number; direction: string; row: number; raw: Record<string,Cell>}[] = [];
    const errors: {row:number; message:string}[] = [];
    const totals = {in:0,out:0,external:0};
    const weights = {in:0,out:0,external:0};
    cells.slice(header+1).forEach((line,index) => {
      const row = header+index+2;
      const values = columns.map(i=>line[i] ?? null);
      if (values.every(value=>!str(value))) return;
      const id = str(values[0]);
      const day = date(values[1]);
      const weight = str(values[8]).replace(/[\s\u00a0]/g,'').replace(',','.');
      const kg = Math.round(Number(weight)*1000);
      const kind = str(values[10]).toLowerCase();
      const direction = kind === 'inleverans' ? 'in' : kind === 'utleverans' ? 'out' : kind === 'externleverans' ? 'external' : null;
      const message = !/^\d{1,32}$/.test(id) ? 'Ogiltigt TransId' : seen.has(id) ? 'Dubblett av TransId i filen'
        : !day ? 'Ogiltigt datum' : !weight || !Number.isFinite(kg) || kg < 0 ? 'Ogiltig vikt' : !direction ? 'Okänd leveranstyp' : '';
      if (message || !direction) {errors.push({row,message});return;}
      seen.add(id);
      const raw = Object.fromEntries(flintabHeaders.map((key,i)=>[key,values[i]]));
      rows.push({id,date:day,kg,direction,row,raw});
      totals[direction]++;
      weights[direction] += kg;
    });
    if (!rows.length) throw Error('Flintabfilen innehåller inga giltiga vägningar.');
    return {sheet,rows,errors,totals,weights};
  }
  throw Error('Filen saknar Flintabs transaktionslista med TransId, Datum, Vikt och Leveranstyp.');
}
