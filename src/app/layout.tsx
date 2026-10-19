import type { Metadata } from "next";
import {RootFrame} from "./_components/root-frame";
import "./globals.css";import "./kpi/kpi.css";
export const metadata:Metadata={title:"Humla",description:"Humla Hub – datamotor och integrationer; Humla Dashboard – KPI och styrning"};
export default function RootLayout({children}:{children:React.ReactNode}){
 return <html lang="sv"><body><RootFrame>{children}</RootFrame></body></html>;
}
