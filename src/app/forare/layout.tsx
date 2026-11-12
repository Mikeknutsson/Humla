import type {Metadata,Viewport} from 'next';
import '@fontsource/nunito-sans/latin-400.css';
import '@fontsource/nunito-sans/latin-700.css';
import './mobile.css';
export const metadata:Metadata={title:'Humla Chaufför',description:'Mina uppdrag och återrapportering',manifest:'/forare/manifest.webmanifest',appleWebApp:{capable:true,title:'Humla Chaufför',statusBarStyle:'default'}};
export const viewport:Viewport={width:'device-width',initialScale:1,themeColor:'#34383e'};
export default function Layout({children}:{children:React.ReactNode}){return <div className="driver-app">{children}</div>;}
