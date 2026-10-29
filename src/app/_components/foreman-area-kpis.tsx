import styles from './foreman-area-kpis.module.css';
export type AreaKpis={required_units:number;covered_units:number;hours_complete:boolean;verified_hours:number|null;worked_hours:number|null;revenue_per_hour:number|null;cost_per_hour:number|null;result_per_hour:number|null;personnel_share:number|null;fuel_share:number|null;repair_share:number|null};
const number=new Intl.NumberFormat('sv-SE',{maximumFractionDigits:1});
const money=new Intl.NumberFormat('sv-SE',{maximumFractionDigits:0});
export function ForemanAreaKpis({kpis}:{kpis?:AreaKpis|null}) {
 if(!kpis)return <section className="panel"><p>Områdets nyckeltal kunde inte hämtas.</p></section>;
 const cards=[['Intäkt / arbetad timme',kpis.revenue_per_hour,'kr/h'],['Kostnad / arbetad timme',kpis.cost_per_hour,'kr/h'],['Resultat / arbetad timme',kpis.result_per_hour,'kr/h'],['Arbetade timmar',kpis.worked_hours,'h'],['Personal / intäkt',kpis.personnel_share,'%'],['Bränsle / intäkt',kpis.fuel_share,'%'],['Reparation / intäkt',kpis.repair_share,'%']] as const;
 return <section className={'panel '+styles.panel} aria-label="Nyckeltal för hela området"><h2>Nyckeltal för hela området</h2><div className={styles.grid}>{cards.map(([label,value,unit])=><article key={label}><span>{label}</span><strong>{value==null?'Underlag saknas':(unit==='kr/h'?money:number).format(value)+' '+unit}</strong></article>)}</div>
 <p>{kpis.hours_complete?'Timvärdena gäller hela området och samma period som sammanställningen.':`Tillförlitligt timunderlag för ${kpis.covered_units} av ${kpis.required_units} enheter. Timvärden för hela området visas när underlaget är komplett.`} Kostnaderna omfattar fördelad overhead. Kostnadsandelarna jämförs med områdets intäkter.</p></section>;
}
