# Daily YTD

The explicit `period_mode=ytd` selection spans September 1 through today's
calendar date in Europe/Stockholm. Previous-year comparisons use the same month
and day in the previous fiscal year, clamping February 29 to February 28.
Historical fiscal years use that same relative cutoff. Future fiscal years do
not allow YTD. Full-year and manually selected complete-month scopes retain
their existing meanings.

The mode survives navigation and saved selections. The server resolves its date
on each new request, rather than treating a saved end date as permanent. Exact
dates participate in report cache keys. Overview, unit follow-up, analysis,
projects, internal summaries, billing balance, workshop hours, monthly reports
and fleet comparisons use the same bounds. Worked hours, capacity, NEXT time and
fuel evidence are bounded as well as financial transactions.

Current-month monthly reports are limited to today; historical comparison loads
receive the matching cutoff. Closed monthly reports retain their full months.
Verified overhead is stored monthly: an unverified partial-month amount remains
missing rather than being prorated without an approved rule.

Validated with period/project tests, TypeScript, changed-file lint, production
build, rolled-back database tests against published financial rows, historical
fleet cutoff and billing balance cutoff. The database test compares both
current and previous revenue to sums over the exact source dates. Source data,
transaction amounts and allocation rules are not changed by a period selection.

Source baseline: production commit 333a0d9335071989e17eb92e4dc505e28b95df48.
