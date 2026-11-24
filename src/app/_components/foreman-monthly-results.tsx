const money=new Intl.NumberFormat('sv-SE',{style:'currency',currency:'SEK',maximumFractionDigits:0});
const monthLabel=new Intl.DateTimeFormat('sv-SE',{month:'short',timeZone:'UTC'});

export type MonthlyUnitResult={unit_id:string|null;month_start:string;result:number};
export type MonthlyResultPair={month:string;current:number|null;previous:number|null};

const series=[
 {key:'current',name:'Valt år',color:'#1769aa'},
 {key:'previous',name:'Föregående år',color:'#a26608'},
] as const;

export function ForemanMonthlyResults({label,months}:{label:string;months:MonthlyResultPair[]}) {
 const values=months.flatMap(({current,previous})=>[current,previous].filter(value=>value!==null));
 if(!values.length)return null;
 const min=Math.min(0,...values),max=Math.max(0,...values);
 const y=(value:number)=>max===min?40:8+(max-value)/(max-min)*60;
 const zero=y(0),step=32,width=months.length*step;
 const formatMonth=(month:string)=>monthLabel.format(new Date(month+'T00:00:00Z'));
 return <figure style={{margin:'0.75rem 0',paddingTop:'0.5rem',borderTop:'1px solid #dce3ea'}}>
  <figcaption><strong>Resultat per månad</strong>{' · '}<small>Vald period</small></figcaption>
  <div style={{display:'flex',flexWrap:'wrap',gap:'0.25rem 0.75rem',fontSize:'0.8rem',marginTop:'0.25rem'}}>
   {series.map(item=><span key={item.key}><span aria-hidden="true" style={{color:item.color}}>■ </span>{item.name}</span>)}
  </div>
  <div style={{overflowX:'auto'}}>
   <svg viewBox={`0 0 ${width} 88`} role="img" aria-label={`Resultat per månad för ${label}, valt år och föregående år`}
    style={{display:'block',width:`min(100%, ${Math.max(width,96)}px)`,minWidth:Math.max(width,96),height:88}}>
    <line x1="0" x2={width} y1={zero} y2={zero} stroke="#8d9bab"/>
    {months.map(({month,current,previous},index)=><g key={month}>
     {series.map(({key,name,color},seriesIndex)=>{
      const value=key==='current'?current:previous;
      if(value===null)return null;
      const bottom=y(value);
      return <rect key={key} x={index*step+6+seriesIndex*11} y={Math.min(bottom,zero)} width="9" height={Math.max(1,Math.abs(zero-bottom))} fill={color}>
       <title>{formatMonth(month)} · {name}: {money.format(value)}</title>
      </rect>;
     })}
     <text x={index*step+step/2} y="84" textAnchor="middle" fontSize="10" fill="currentColor">{formatMonth(month)}</text>
    </g>)}
   </svg>
  </div>
  <details style={{fontSize:'0.8rem'}}>
   <summary>Visa månadsbelopp</summary>
   <div className="table-wrap"><table>
    <thead><tr><th scope="col">Månad</th><th scope="col">Valt år</th><th scope="col">Föregående år</th></tr></thead>
    <tbody>{months.map(({month,current,previous})=><tr key={month}>
     <th scope="row">{formatMonth(month)}</th><td>{current===null?'Underlag saknas':money.format(current)}</td>
     <td>{previous===null?'Underlag saknas':money.format(previous)}</td>
    </tr>)}</tbody>
   </table></div>
  </details>
 </figure>;
}
