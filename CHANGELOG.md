# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [1.1.0] — 2026-08-29

A release about the parts of the app that were missing rather than the parts
that were wrong: money can now be edited, searched, budgeted, attributed to an
account, exported and locked away.

### Added

- **Transaction editing.** Records could only be created and deleted, so a
  mistyped amount meant deleting the row and entering it again. Editing keeps
  the original id, so the record is replaced rather than duplicated, and the
  recurring link and auto-generated flag survive.
- **A date field when recording.** Every manual entry used to be stamped with
  the moment it was typed, so a receipt entered the next morning landed on the
  wrong day and moved money between months.
- **Search, filters and sorting** across the whole history — by title or
  category, direction, period, category set, and four sort orders.
- **Budgets**, per category or across all spending. Progress is reported three
  ways: what is left, what the current pace projects by month end, and roughly
  what can be spent per day without going over. The figures are given to the
  assistant, so it holds you to limits you chose instead of inventing them.
- **Accounts** — cash, bank, wallets and cards, each with an optional opening
  balance and its own running balance.
- **Transfers between accounts**, stored as a paired pair of rows that move
  each balance without counting as income or spending.
- **Receipt photos** attached to any transaction, from the camera or gallery,
  viewable full size. Stored on the device rather than uploaded.
- **App lock** behind the device biometric or PIN, re-arming when the app is
  backgrounded.
- **CSV export** of transactions and budgets through the share sheet.
- **Account deletion**, clearing every stored record and closing the account.
- **Currency setting** — NPR, INR, USD, EUR and GBP. Symbol and digit grouping
  only; nothing is converted, since the app holds no exchange rate.
- **Mark a bill reminder paid**, which records the expense against the due
  date and rolls the reminder to next month.
- **273 tests**, up from 156.

### Changed

- Amounts group digits the South Asian way for rupees — `85,38,550` rather
  than `8,538,550`. Full and compact figures previously disagreed, so one
  screen could describe the same magnitude two different ways.
- Tapping a row in the transaction list opens it for editing. It used to open
  the delete confirmation, making a stray tap the first step of destroying a
  record.
- The transaction list shows income as well as expenses.
- Category icons come from the shared icon map rather than a local switch that
  named categories no longer in the vocabulary, so every row fell through to a
  default icon.

### Fixed

- **Expenses displayed as income.** Every read ran the title and category
  through a keyword list — `gift`, `business`, `investment`, `refund` and more
  — and forced the direction to income on a substring match. An expense filed
  under "Shopping - Gift" came back as income and reached the balance, the
  savings rate, every chart, the PDF and the figures the assistant was given.
  The stored value was correct throughout; only the read was wrong.
- **Release builds could not be produced at all.** R8 aborted on ML Kit
  recogniser classes that are not dependencies. Debug builds skip
  minification, which is why nothing caught it.
- **Receipt scanning was dead in release builds.** R8 removed the no-argument
  constructors Firebase instantiates reflectively, so every ML Kit registrar
  failed at startup. Nothing crashed, so only a device showed it.

### Known issues

- PDFs cannot render Devanagari; unsupported characters are dropped rather
  than drawn as boxes.
- The application id is still `com.example.smartexpense`, which Play rejects.
  Changing it orphans existing installs, so it needs doing deliberately.
- Release builds are signed with the debug keystore.
- Receipt images are not backed up and do not follow the account to another
  device.

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
  *investment* can be displayed as income. *Fixed in 1.1.0.*
- Transactions cannot be edited, only deleted. *Fixed in 1.1.0.*
- PDFs cannot render Devanagari; unsupported characters are dropped rather
  than drawn as boxes.
