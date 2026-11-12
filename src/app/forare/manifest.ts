import type {MetadataRoute} from 'next';
export default function manifest():MetadataRoute.Manifest{return {id:'/forare',name:'Humla Chaufför',short_name:'Chaufför',start_url:'/forare',scope:'/forare',display:'standalone',background_color:'#f1f2f3',theme_color:'#34383e',icons:[{src:'/forare/icon.svg',sizes:'any',type:'image/svg+xml',purpose:'any'}]};}
