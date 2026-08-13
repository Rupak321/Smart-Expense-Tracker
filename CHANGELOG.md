# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [1.0.0] — 2026-08-13

First tagged release. The app was rebuilt across its interface, its financial
reasoning and its reporting.

### Added

- **Design token system** (`AppTokens`, `AppColorRoles`) covering radii,
  spacing, motion and semantic colour roles, with full light and dark themes
  and component themes for dialogs, sheets, chips, switches and snackbars.
- **Financial insights engine** — exact all-time totals, month-over-month
  difference, savings rate, daily burn, runway, projected month end,
  per-category deltas and upcoming commitments, computed as a pure function.
- **Data-driven coaching stance** — the assistant's tone (calm, encouraging,
  watchful, strict) is derived from the figures rather than chosen at random.
- **Reports** — seven real reporting periods, each compared against the
  equivalent preceding window; a full-screen in-app report; and a designed
  multi-page PDF with a cover band, KPI tiles, category chart, tables and page
  numbering.
- **Category vocabulary** — categories as first-class records with a kind
  (expense, income or either), icon and colour; a local matcher that resolves
  free text against the existing vocabulary; and management screens for
  rename, merge, delete and duplicate cleanup.
- **One-off income flag**, excluded from savings rate and averages while still
  counting towards income and balance.
- **Password reset**, inline authentication errors, and autofill support.
- **156 tests** covering insight maths, report periods, category matching,
  money formatting and layout overflow.

### Changed

- Bottom navigation gained labels, semantics and 44dp hit areas, and no longer
  animates on tap.
- The assistant's chat history is windowed rather than replayed in full.
- Default AI model is now `openai/gpt-oss-20b`; `llama-3.1-8b-instant` is
  scheduled for shutdown on 16 August 2026.
- The login screen was rebuilt around the app's own branding and design
  tokens.

### Fixed

- **Assistant quoted incorrect totals.** The prompt summed only the 18 most
  recent transactions and labelled the result a lifetime total, so every total
  and affordability verdict was computed from a truncated window.
- **Amount parsing merged numbers.** Every non-digit was stripped before
  parsing, so `spent 500 on 2 coffees` became 5002 and `1200 rent for july
  2026` became 12002026.
- **Report periods did nothing.** The chosen period was never applied to the
  query, so all four options produced an identical all-time report.
- **Report export was unreadable.** The report was flattened to a single
  string with its markdown and newlines removed, truncated at 2,200
  characters, and printed on one page that clipped anything taller.
- **PDF rendered missing-glyph boxes** where text contained characters outside
  the built-in font, such as an em dash.
- **Cards were invisible.** The scaffold and every card were painted with the
  same `colorScheme.surface`.
- **Infinite rebuild loop** in the assistant screen, caused by a StreamBuilder
  that rebuilt its stream every build and compared message lists by identity.
- **Silent transaction saves.** A misparsed amount was written to the ledger
  with no confirmation and no undo; every mutation is now confirmed.
- **Questions treated as transactions** — "should I send 5000 to mom?" matched
  a high-confidence rule and was offered for saving.
- **Duplicate chart colours**, where two categories matching the same keyword
  were drawn identically in both the donut and the legend.
- **Layout overflow** in category rows, trend headers, metric cards, the
  bill-reminder sheet and the recurring form.
- Network failures surfaced as raw Dart exceptions rather than plain language.

### Known issues

- Income and expense direction is overridden at read time by a keyword
  heuristic, so an expense containing words such as *gift*, *business* or
  *investment* can be displayed as income. Scheduled for the next release.
- Transactions cannot be edited, only deleted.
- PDFs cannot render Devanagari; unsupported characters are dropped rather
  than drawn as boxes.
