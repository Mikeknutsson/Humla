import Mobile from '../mobile';
import {HomeSummary} from '../home-summary';

export default function Demo(){
 return <Mobile demo summary={<HomeSummary demo period={{from:'2026-11-02',to:'2026-11-08'}}
  report={{status:'ready',reporting:'good',latest_work_date:'2026-11-06'}}/>}/>;
}
