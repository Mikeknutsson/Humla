"use client";
import {createContext,useContext} from 'react';

export type ReportSelection={query:string;pending:boolean;change:(query:string)=>void};
export const KpiReportSelection=createContext<ReportSelection|null>(null);
export function useKpiReportSelection(){return useContext(KpiReportSelection);}
