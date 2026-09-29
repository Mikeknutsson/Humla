export const ACCOUNT_CATEGORIES = {
  personnel: "Personal",
  fuel: "Bränsle",
  service_repair: "Service & reparation",
  fixed: "Fasta",
  other: "Övrigt",
  ballast: "Ballast",
  disposal: "Deponi",
} as const;

export const CALCULATION_ROLES = {
  cost: "Kostnad",
  fuel: "Bränslekostnad",
  exclude: "Exkludera",
} as const;

export type AccountCategory = keyof typeof ACCOUNT_CATEGORIES;
export type CalculationRole = keyof typeof CALCULATION_ROLES;

export type AccountMapping = {
  id: string;
  account_from: number;
  account_to: number;
  name: string;
  calculation_role: CalculationRole;
  cost_category: AccountCategory;
  include_in_vehicle_result: boolean;
  priority: number;
  valid_from: string;
  valid_to: string | null;
  enabled: boolean;
  notes: string | null;
  created_at: string;
  updated_at: string;
};

export function validRoleCategory(role: CalculationRole, category: AccountCategory) {
  if (role === "fuel") return category === "fuel";
  return role === "cost" || role === "exclude";
}
