# Saw foreman cost detail and registered material value

The foreman scorecard exposes a scoped saw_breakdown from the same authorized, dated canonical-unit facts as its summary. Management and remaining costs partition the existing cost total. Truck compensation follows the existing saw-hour rule and is already deducted from saw revenue; displaying it does not deduct it again.

Registered saw-linked Grot/Stock is valued at the configured 600 SEK/ton. Approved weigh tickets take priority within the existing covered period and for matched orders. Outside that coverage, scoped Workify articles 3-09 and 3-24 in tons on confirmed saw orders are used, including zero-priced material rows. Existing source eligibility rules apply. Content keys with per-batch occurrence ordinals remove repeated exports while retaining legitimate repeated lines. Unlinked material is not assigned to saw.

The material value is a derived revenue fact, identified by _humla_saw_chip. It is a calculated material value, not a customer payment. Raw imports and the separate payment forecast remain unchanged. The nightly worker rebuilds the projection after overhead. Replays replace only these derived facts.

The current historical approved weigh basis is 209 tickets, 865.75 tons, 519450 SEK. The current year has five linked Workify entries totaling 33.60 tons, 20160 SEK. Period, month, responsibility and group filters apply through existing report authorization. Trend and hourly metrics use the same facts.

Validation: source/cost conservation, replay equality, historical and current quantity/rate totals, unique derived IDs, prepared/display equality, month filtering, summary/trend reconciliation, own-profile access and cross-profile denial. SQL checks roll back.
