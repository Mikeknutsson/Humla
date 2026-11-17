export const costColumns=[
 {key:'personnel',label:'Personal',color:'59,130,246'},
 {key:'fuel',label:'Bränsle',color:'217,119,6'},
 {key:'service_repair',label:'Service/Rep',color:'168,85,247'},
 {key:'fixed',label:'Fasta',color:'100,116,139'},
 {key:'depreciation',label:'Avskrivning',color:'20,140,140'},
 {key:'management',label:'Arbetsledning',color:'99,102,241'},
 {key:'overhead',label:'Overhead',color:'107,114,128'},
 {key:'other',label:'Övrigt',color:'148,105,69'},
 {key:'material',label:'Material',color:'22,163,74'},
 {key:'tipp_deponi',label:'Tipp/Deponi',color:'180,83,9'},
 {key:'hired',label:'Inhyrda',color:'219,39,119'},
] as const;
export function costShare(amount:number|null,revenue:number){return amount!==null&&revenue>0?amount/revenue*100:null;}
export function costShade(color:string,share:number|null){return share===null||share===0?'transparent':share<0?'#f1f5f9':'rgba('+color+','+(0.04+Math.min(share,100)/100*0.32)+')';}
