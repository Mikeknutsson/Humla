# Approved provisional supplier work costs

When a supplier cost is missing for a reporting month, an explicit user approval can create a separate estimate linked to the canonical economic unit. The amount is derived from verified published cost facts for the approved reference month, not duplicated source import rows. The approval retains the reference fact IDs, reference generation and method.

The Hub publishes one stable derived fact and its display projection, with source `Preliminär arbetskostnad`, category `personnel`, a clear provisional description and the approval metadata. It is not a NEXT invoice, does not create an import or voucher, has no invented invoice number, and is excluded from the external-invoice billing balance.

Publication checks for actual NEXT supplier costs in the same booked calendar month. When actual costs exist, only the recoverable derived estimate is removed from both projections; the approval and original reference evidence remain. Subsequent publications stay idempotent. No service dates or invoice hours are inferred from booked dates.

The maintenance script resolves the canonical LMT31J unit and calculates the approved previous-month sum from published, deduplicated supplier costs. It stops if a valid supplier cost is already imported for the target month. It verifies that the cost increase is exactly the approved amount and increments the report correction revision without starting a full report worker.

Validation: reference-month evidence inspected; report category and unit totals verified; rollback-only tests for idempotence and automatic estimate suppression by actual costs; browser verification of the provisional cost line.
