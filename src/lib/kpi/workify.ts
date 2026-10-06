import type { ParsedTable } from './schema';
import type { normalizeRows } from './parser';
export type ArticleRule = { id: string; article_number: string; project_reference: string | null; cost_center: string | null; source_hash: string; revenue_category?: string };
export function isWorkify(table: ParsedTable) {
  return ['Ordernummer','Artikelnummer','Artikeldatum','Summa','Fakturerad'].every(h => table.headers.includes(h));
}
export function allocateWorkify(rows: Array<ReturnType<typeof normalizeRows>[number] & { vehicle_object_id?: string | null }>, rules: ArticleRule[]) {
  const byArticle = new Map(rules.map(rule => [rule.article_number.trim().toUpperCase(), rule]));
  return rows.map(row => {
    if (row.amount === 0 || (row.amount === null && !String(row.source_data.Summa ?? '').trim())) return { ...row, amount: 0, vehicle_registration: null, vehicle_object_id: null, is_valid: true, validation_errors: [], allocation: { target: 'ignored', resolution: 'workify_no_amount' } };
    const article = (row.source_data.Artikelnummer ?? '').trim().toUpperCase();
    const rule = byArticle.get(article);
    if (!rule) return { ...row, is_valid: false, validation_errors: [...row.validation_errors, `Ej mappad Workify-artikel: ${article || '(saknas)'}`], allocation: { article, target: 'review' } };
    if (rule.revenue_category === 'ignored') {
      const errors = row.validation_errors.filter(error => error !== 'Fordonsbeteckning saknar verifierad regnummerkoppling');
      if (row.amount !== 0) errors.push('Ignorerad informationsartikel har ett belopp som behöver granskas');
      return { ...row, project_reference: null, vehicle_registration: null, vehicle_object_id: null,
        allocation: { article, rule_id: rule.id, target: 'ignored' }, validation_errors: errors, is_valid: errors.length === 0 };
    }
    const project = rule.project_reference;
    // Project allocation must not also match a vehicle or person reporting unit.
    const errors = project ? row.validation_errors.filter(e => e !== 'Fordonsbeteckning saknar verifierad regnummerkoppling' && e !== 'Motstridiga fordonskopplingar') : [...row.validation_errors];
    if (!project && !row.vehicle_registration) errors.push('Workify-artikeln ska till fordon: registreringsnummer behöver mappas');
    return { ...row, project_reference: project, vehicle_registration: project ? null : row.vehicle_registration, vehicle_object_id: project ? null : row.vehicle_object_id, employee_number: null,
      cost_center: rule.cost_center ?? row.cost_center,
      allocation: { article, rule_id: rule.id, source_hash: rule.source_hash, target: project ? 'project' : 'vehicle', original_project: row.project_reference, original_vehicle: row.vehicle_registration },
      validation_errors: errors, is_valid: errors.length === 0 };
  });
}
