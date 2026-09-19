# friendlyfolio

Self-hosted photo galleries for [Friendly.rb](https://friendlyrb.com), replacing
the hosted wfolio service. Rails 8.1 on SQLite, one box, Avo for the admin.

It hosts our own conference galleries and nothing else. There are no customer
accounts, no sign-up, and no client-proofing machinery.

## Running it

```bash
bin/setup
ADMIN_EMAIL=you@friendlyrb.com ADMIN_PASSWORD=... bin/rails db:seed
bin/dev
```

The admin lives at `/avo` and is unreachable without signing in — it is mounted
inside a Devise `authenticate` block, so the route does not exist for anonymous
visitors rather than merely redirecting them.

## Getting photos in

Ingest is a rake task, not a browser upload. ~1,900 photos and 15 GB do not
belong in a form post.

**Strip GPS first.** The download button hands out the photographer's original
file, so stripping metadata from derivatives alone would still leak attendee
locations to anyone who downloads a photo. This is lossless and leaves
copyright and artist tags intact:

```bash
exiftool -gps:all= -overwrite_original /path/to/photos
```

Then ingest and bake:

```bash
bin/rails "photos:ingest[2025,day-1,/path/to/photos/day-1]"
bin/rails "photos:preprocess[2025]"
bin/rails "photos:verify[2025]"     # must report nothing missing before publishing
```

**Bake locally, then copy up.** AVIF encoding dominates the pipeline; running it
on the server competes with Puma for cores and risks an OOM. Ingest and bake on
a laptop, then transfer `storage/`.

Note that this moves *both* halves of Active Storage — the files on disk and the
database rows describing them. Since the database is itself a file under
`storage/`, one transfer carries both, which means the initial import
**replaces** the production database rather than merging into it. That is
correct for the first import and wrong for every later one.

Nothing renders publicly until its derivatives exist: Active Storage generates a
missing variant synchronously inside the request, so an unbaked photo would put
libvips in a visitor's request path. `photos:verify` is the gate.

## Deployment

Hatchbox, single box, Caddy in front.

Hatchbox symlinks `storage/` to a shared directory on every deploy, so both the
SQLite databases (`storage/db/`) and the Active Storage files (`storage/files/`)
survive releases with no extra configuration. **Verify this on the box before
relying on it** — the split into `db/` and `files/` is ours, and the documented
default is a flat `storage/`:

```bash
readlink -f /home/deploy/<app>/current/storage
```

Required environment: `SECRET_KEY_BASE`, `ADMIN_EMAIL`, `ADMIN_PASSWORD`.

### Publication is a one-way door

Unpublishing a gallery closes every route this app serves for it. It does not
revoke image URLs that are already out there: Active Storage's proxy controller
verifies the signed blob id and knows nothing about publication, so a derivative
URL someone captured while the gallery was public keeps working — and a CDN in
front will happily keep serving it.

There is a test asserting exactly this (`test/integration/unpublished_bytes_test.rb`),
so the behaviour is recorded rather than assumed. If a photo genuinely has to be
retracted, delete it; unpublishing is not enough.

A job worker must be running. Solid Queue is installed and wired up, but Rails
only starts it inside Puma when `SOLID_QUEUE_IN_PUMA` is set — otherwise run
`bin/jobs` as a separate process, which is the better shape here since libvips
then competes with nothing for the web workers' threads.

Without a worker, variants for newly uploaded photos are never generated and
the first visitor pays for them synchronously inside the request. Nothing in
the test suite catches this, because tests run jobs inline — the only proof is
attaching a photo on the real box and watching its derivatives appear.

### Put a CDN in front

This is architectural, not an optimisation. There is no Active Storage URL on a
disk service that bypasses Rails — `public: true` only removes the expiry from
the signed token, and proxy mode streams through `ActionController::Live`, so
`X-Sendfile` cannot apply either. Without a CDN this box serves every byte of
every wall view, forever.

Rails already emits a permanent, long-lived public `Cache-Control` on variant
URLs, so Cloudflare's free tier needs no header configuration. Verify it is
actually caching — fetch a derivative twice and confirm the second is served
from the edge.

Two rules follow, and both look harmless to break:

- **Never set `config.active_storage.urls_expire_in`.** An expiry makes every
  render emit a different URL: zero cache hits, and a CDN full of URLs that
  later 404.
- **Treat `SECRET_KEY_BASE` as permanent.** It signs every derivative URL, so
  rotating it breaks every cached URL and every link anyone has shared. The one
  exception is a compromised key — then rotate, and accept that cost.

### Backups

Register the primary database with Hatchbox at its **shared** absolute path, not
a release path, which changes every deploy.

Hatchbox's backups cover the database only. The ~15 GB under `storage/files/` is
the bulk of the data and the thing this app exists to hold, and nothing here
backs it up. It needs its own answer.
