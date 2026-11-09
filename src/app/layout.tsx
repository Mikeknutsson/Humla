import type {Metadata} from "next";
import {AppFrame} from "./_components/app-frame";
import "./globals.css";
import "./kpi/kpi.css";

export const metadata:Metadata={title:{default:"Humla Portal",template:"%s | Humla"},description:"Gemensam portal för Humlas verksamhetsmoduler och integrationsnav."};

export default function RootLayout({children}:{children:React.ReactNode}){
 return <html lang="sv"><body><AppFrame>{children}</AppFrame></body></html>;
}
