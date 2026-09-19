# Residual Review Findings — feat/photo-galleries

Seven persona reviewers read the plan and one read the code. The defects they
found are fixed and committed. What follows is what was **not** actioned, with
the reason, so none of it is lost by being merely decided against.

There is no remote on this repository, so these have no tracker tickets. This
file is the durable record.

## Known limitations, deliberately shipped

- **Unpublishing does not revoke bytes already handed out.** Active Storage's
  proxy controller authorises on the signed blob id alone. R34 now says this,
  `test/integration/unpublished_bytes_test.rb` pins it, and the README calls
  publication a one-way door. To retract a photo, delete it.
- **Active Storage files have no backup.** Hatchbox's SQLite backups cover the
  database; the ~15 GB under `storage/files/` is the bulk of the data and the
  thing the app exists to hold. Flagged in the README and in the plan's Risks.
- **A CDN is architectural, not optional.** Without one this box serves every
  byte of every wall view forever. Nothing in the repo can enforce it.
- **`exiftool` is not installed here.** Ingest refuses GPS-bearing files rather
  than importing them, and `PHOTOS_GPS_SCANNER=vips` is an opt-in detector for
  machines without it. The lossless strip still needs exiftool.

## Deferred scope

- **Bulk zip download** at section and gallery scope. The reference offers it at
  three scopes; this is the one genuine parity gap. Deferred because building a
  4.66 GB archive on a single box is an operational decision, not an
  implementation detail. **No gate forces this decision before launch** — the
  product reviewer flagged that, and it remains true.
- **An attendee looking for photos of themselves is served by nothing.** Search
  is deferred, people-search is rejected as SaaS machinery, and bulk download is
  deferred. The product reviewer rated this the sharpest product gap; the
  Actors section never names that job. Worth deciding deliberately rather than
  by omission.
- **Cutover is unowned.** The objective is replacement, but nothing updates
  `friendlyrb.com`'s three edition pages or ends the wfolio subscription, so
  every gate here can pass with the old service still being paid for.
- **The replace-versus-stay decision is priced on neither side.** Neither
  wfolio's cost nor this box's running cost appears anywhere, so "was this worth
  it" cannot be answered from the documents.

## Judgement calls left as-is

- **R13's no-JS photo fallback** was called unrequested scope: sections past the
  first are Turbo Frames, so a JS-off visitor can open a shared photo but cannot
  browse the wall it came from. Kept — it fell out of using a real route rather
  than a query parameter, and cost nothing extra.
- **The 300-photo pagination threshold** has no derivation. One real section
  exceeds it (2024 day-1, 342) and one sits just under (2023 day-1, 299), which
  is close enough that it should not be treated as finely tuned.
- **The derivative storage budget disagrees with itself.** The plan says 9–14 GB
  while KTD8's own per-variant figures sum to roughly 1 MB per photo, which
  would be ~2 GB. Measure on the first real gallery.
- **Hatchbox's shared-storage layout is still unobserved.** Two current sources
  name `storage` among the symlinked paths, but the `storage/db` and
  `storage/files` split is ours and departs from the documented default. U12
  verifies it on the box; nothing here can.
- **Avo uses `ActiveSupport::Configurable`**, which Rails 8.1 deprecates and 8.2
  removes. Nothing breaks today — a real boot produced no deprecation output —
  but it is a Rails 8.2 upgrade blocker to re-check.

## Not reproduced

`avo-advanced_file_uploads`, the paid add-on the plan named as covering bulk
upload, does not appear in Avo 4.2.5's package map. Buying out of the
single-file limit may not be an available option; the rake task is the answer
either way.
