import type {CheckedLoad, Invoice} from './johansson-material';

export const reviewLabels = {todo: 'Att granska', in_progress: 'Pågår', reviewed: 'Granskad'} as const;
export type ReviewState = keyof typeof reviewLabels;
export type DocumentEntry = {
  key: string;
  name: string;
  source: {subject: string | null; received_at: string | null} | null;
  updated_at: string;
  approved_at: string | null;
};
type CheckedInvoice = Omit<Invoice, 'loads'> & {loads: CheckedLoad[]};
export type MaterialReview = DocumentEntry & {
  invoices: CheckedInvoice[];
  skipped: string[];
  revision: number;
  billing_review?: true;
  billing_match_version?: 3;
  statuses: Record<string, {state: ReviewState}>;
};

export const hasWorkifyCharge = (load: CheckedLoad) => (load.workify_rates ?? []).some(rate => rate > 0);

export function isDeviation(load: CheckedLoad, billingReview?: true) {
  if (billingReview) return !hasWorkifyCharge(load);
  return !['matched', 'equivalent'].includes(load.match) || load.amount === null || load.workify_registrations.length !== 1;
}

export const deviationKey = (sheet: string, item: number | string) => JSON.stringify([sheet, item]);
