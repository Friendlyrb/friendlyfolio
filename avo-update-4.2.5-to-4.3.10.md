# Avo update log — 4.2.5 → 4.3.10

Scratch notes from an assisted Avo update on 2026-11-02. Not part of the app —
**safe to delete once the upgrade is reviewed and merged.**

Done as part of a security update: bundler-audit flagged avo 4.2.5
(GHSA-h7x6-9mqf-vgmx, GHSA-x65r-p6hf-94hv; fixed in >= 4.3.4). Updated with
`bundle update --conservative avo` alongside the other flagged gems.

## Versions

| Gem | Before | After |
| --- | ------ | ----- |
| avo | 4.2.5  | 4.3.10 |

No Avo add-on gems are installed.

## Guide sections

| Section | Status | Notes |
| ------- | ------ | ----- |
| 4.3.9 — actions check `act_on?`; 403 instead of redirect | NOT USED | No Avo actions or policies (`authorization_client = nil`) |
| 4.3.6 — Trix uploads authorized with `create?` | NOT USED | No Trix fields |
| 4.3.2 — fields read `activerecord.attributes` locale keys | NOT USED | No `activerecord:` / `attributes:` keys in `config/locales` |
| 4.3.1 — back-navigation restores selection; badges on forms; `set_locale` | NOT USED | No badge fields with `except_on`/`show_on`; no `set_locale` |
| 4.3.0 — avo-api token entitlements | NOT USED | No avo-api |
| `attach_scope` honored on save | NOT USED | Only a `belongs_to` cover picker uses `attach_scope` |
| Duplicate field declarations / `fields_by_database_id` | NOT USED | None found |
| `warn_on_unsaved_changes` on by default | APPLIES (behavior) | Admins now get a confirm dialog when leaving a form with unsaved edits. No system tests affected. |
| Neutral theme shades changed | REVIEWED | `admin.css` styles only the importer, not Avo shades |
| Add-on sections (kanban, menu, api, …) | NOT USED | No add-ons installed |

## Verified

- 146 tests pass; RuboCop, Brakeman, bundler-audit and importmap audit clean.
- Chromium against a dev copy: Photos index thumbnails, gallery show, and the
  custom Import photos tool (its Stimulus controller connects through the
  `_head` partial override) work, with no console errors under the CSP.

## Manual verification needed

- Look over Avo's chrome for the new neutral shades.
