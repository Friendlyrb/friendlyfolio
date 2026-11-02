<p align="center">
  <img src="public/apple-touch-icon.png" width="72" height="72" alt="Friendly.rb pixel ruby">
</p>

<h1 align="center">Friendly.rb Photos</h1>

<p align="center">
  Self-hosted photo galleries for <a href="https://friendlyrb.com">Friendly.rb Conf</a> —
  every edition, every day, every hallway conversation someone pointed a camera at.
</p>

<p align="center">
  <a href="https://photos.friendlyrb.com"><strong>photos.friendlyrb.com</strong></a> ·
  <a href="https://github.com/Friendlyrb/friendlyfolio/actions/workflows/ci.yml"><img src="https://github.com/Friendlyrb/friendlyfolio/actions/workflows/ci.yml/badge.svg" alt="CI status" align="center"></a>
</p>

---

**friendlyfolio** replaces the hosted wfolio service with one small Rails app. It hosts the conference's own galleries and nothing else: no customer accounts, no sign-up, and no client-proofing machinery.

| | |
| --- | --- |
| **Stack** | Rails 8.1 · Ruby 3.4.5 · SQLite · Solid Queue / Cache · Propshaft + importmap + Stimulus |
| **Admin** | [Avo](https://avohq.io) at `/avo`, behind Devise |
| **Images** | libvips: AVIF + WebP variants, a JPEG for sharing, blurhash placeholders |
| **Storage** | Cloudflare R2, fronted by Cloudflare's CDN |
| **Hosting** | Hatchbox, one box, Caddy in front |

## Contents

- [Quick start](#quick-start)
- [Running with Docker](#running-with-docker)
- [Tests and CI](#tests-and-ci)
- [Getting photos in](#getting-photos-in)
- [How publishing works](#how-publishing-works)
- [Deployment](#deployment)
- [Project layout](#project-layout)

## Quick start

You need **Ruby 3.4.5** and **libvips with AVIF support**:

| Platform | Install libvips |
| --- | --- |
| macOS | `brew install vips` |
| Debian / Ubuntu | `apt install libvips42 libheif-plugin-aomenc libheif-plugin-dav1d` |

You also want [exiftool](https://exiftool.org) (`brew install exiftool`) to import photos in bulk.

```bash
bin/setup              # gems, database, then starts bin/dev
bin/rails db:seed      # admin: adrian@adrianthedev.com / secreto
```

Open **<http://localhost:3000>**; the admin is at **/avo**. `bin/dev` runs the web server, the Tailwind watcher and the job worker that bakes photo variants.

> [!NOTE]
> Those credentials are a development default only. In production, seeding creates an admin only from `ADMIN_EMAIL` and `ADMIN_PASSWORD`. There is no default account, because a known password on a public box is not a convenience.

The admin is unreachable without signing in. It is mounted inside a Devise `authenticate` block, so for anonymous visitors the routes do not exist at all, rather than redirecting.

## Running with Docker

The `Dockerfile` builds the production image: Ruby 3.4.5, libvips with the AV1 encoder, and assets precompiled. `compose.yaml` runs it as a web server plus a separate job worker that share one `storage` volume.

```bash
echo "SECRET_KEY_BASE=$(openssl rand -hex 64)" > .env
echo "ADMIN_EMAIL=you@example.com" >> .env
echo "ADMIN_PASSWORD=$(openssl rand -base64 18)" >> .env

docker compose up --build
```

Then open **<http://localhost:3000>**. The entrypoint prepares all three databases and seeds the admin. The port is bound to `127.0.0.1` only: Compose serves plain HTTP, so it is not exposed to the rest of the network.

Compose runs the production build with a few local-only switches. **None of them belong on a public deployment:**

| Variable | Compose default | Why |
| --- | --- | --- |
| `ACTIVE_STORAGE_SERVICE` | `local` | Disk storage instead of R2 |
| `RAILS_FORCE_SSL` | `false` | Plain `http://localhost` |
| `CANONICAL_URL` | `http://localhost:3000` | Canonical and social links that include the port |

Set `ACTIVE_STORAGE_SERVICE=r2` and the `R2_*` variables to run against a real bucket. For day-to-day development, `bin/dev` is still faster.

## Tests and CI

```bash
bin/rails test     # the suite
bin/rubocop        # lint
bin/ci             # everything CI runs, in order (config/ci.rb)
```

GitHub Actions ([`ci.yml`](.github/workflows/ci.yml)) runs on every pull request. Every job runs inside `ruby:3.4.5`:

| Job | Runs |
| --- | --- |
| **Lint** | RuboCop (`rubocop-rails-omakase`) |
| **Security audits** | Brakeman, bundler-audit, importmap audit |
| **Tests** | the suite, then the seeds |
| **Build** | a production asset precompile |
| **Docker image** | builds the `Dockerfile` |

> [!IMPORTANT]
> The photo tests bake real AVIF. A libvips without the AV1 encoder fails them all with `heifsave: Unsupported compression`, so if they fail locally, check that first.

## Getting photos in

There are two paths, and the right one depends on how many photos you have.

### Drop a folder (tens of photos)

Sign in, then choose **Tools → Import photos** in the Avo sidebar.

Pick the gallery and the section, then drop a folder or some files. The section choice decides where everything lands:

- an existing section;
- a new one you name;
- or **Use folder names**, which reads the folder structure, so `day-1/DSC_0001.jpg` lands in a section called `day-1`, created if needed.

Files upload straight to storage rather than through a Rails request, so size is not the constraint; server CPU is. Each photo costs about **12 seconds of baking**. A few dozen photos take minutes, and a whole edition takes hours of the box's time while it is also serving the site.

Re-dropping the same folder is safe: files already imported are skipped by content digest. Photos carrying GPS, or that cannot be checked for it, are rejected, and the page says which ones and why.

### Rake tasks (a whole edition)

For hundreds of photos, ingest and bake on a laptop, then copy the result up. About 1,900 photos and 15 GB do not belong in a browser tab.

**1. Strip GPS.** The download button hands out the photographer's original file, so GPS in it publishes where an attendee was standing. This is lossless, and it leaves the copyright and artist tags intact:

```bash
exiftool -gps:all= -xmp:geotag= -overwrite_original /path/to/photos
```

**2. Ingest, bake and verify:**

```bash
bin/rails "photos:ingest[2025,day-1,/path/to/photos/day-1]"
bin/rails "photos:preprocess[2025]"
bin/rails "photos:verify[2025]"     # must pass before publishing
```

**3. Copy up.** AVIF encoding dominates the pipeline. Running it on the server competes with Puma for cores and risks running out of memory, so bake on a laptop and transfer `storage/`.

> [!WARNING]
> `storage/` holds *both* halves of Active Storage: the files and the database rows that describe them. So the first import **replaces** the production database rather than merging into it. That is right for the first import and wrong for every later one.

To move objects that already live on the box's disk to R2:

```bash
bin/rails storage:to_r2_check   # report only, changes nothing
bin/rails storage:to_r2         # copy, then repoint the blob rows (restartable)
```

Photos imported before blurhash placeholders existed fall back to their dominant colour. To re-derive their metadata, run this once. It downloads every original, so run it where that is cheap:

```bash
bin/rails runner 'Photo.find_each(&:extract_image_metadata)'
```

## How publishing works

A photo is shown publicly only when it is **displayable**: all nine variants are baked **and** it does not carry location data. `Photo.displayable` enforces both, so no code path that marks a photo ready can expose a GPS-tagged original.

- **GPS detection fails closed.** It checks EXIF and the XMP packet, and a photo that cannot be read, or whose scan errors, counts as carrying GPS.
- **Nothing renders unbaked.** Active Storage would generate a missing variant inside a visitor's request. `photos:verify` is the gate, and it also fails any gallery holding a GPS-flagged photo.
- **Galleries are drafts until published.** Only signed-in admins can see an unpublished gallery.

### Publication is a one-way door

Unpublishing a gallery closes every route this app serves for it. It does **not** revoke image URLs that are already out there: Active Storage verifies the signed blob id and knows nothing about publication, so a URL captured while the gallery was public keeps working, and the CDN keeps serving it.

> [!CAUTION]
> **Review unpublished galleries locally, not on the deployed site.** The page is private for a signed-in admin, but the images on it are not. Previewing from the box pushes their full-size bytes into the CDN at permanent public URLs, which is exactly what publication exists to prevent. The app shows a warning banner on unpublished galleries for this reason.

`test/integration/unpublished_bytes_test.rb` asserts this behaviour, so it is recorded rather than assumed. To retract a photo, delete it; unpublishing is not enough.

## Deployment

Hatchbox, one box, Caddy in front, Cloudflare at the edge.

### Environment

| Variable | Required | Purpose |
| --- | --- | --- |
| `SECRET_KEY_BASE` | ✅ | Signs sessions **and every image URL** (see below) |
| `ADMIN_EMAIL`, `ADMIN_PASSWORD` | ✅ | The admin account that seeding creates |
| `APP_HOST` | ✅ | The public hostname (`photos.friendlyrb.com`). It turns on host authorization, and canonical, `og:*`, sitemap and `robots.txt` URLs are built on it |
| `R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_BUCKET` | ✅ | Photo storage |
| `R2_PUBLIC_HOST` | recommended | The bucket's custom domain. Image URLs then point straight at the CDN, and Puma never serves a byte |
| `SOLID_QUEUE_IN_PUMA` | | Runs the job worker inside Puma (otherwise run `bin/jobs`) |
| `JOB_CONCURRENCY`, `RAILS_MAX_THREADS`, `RAILS_LOG_LEVEL` | | Tuning |

### Storage on the box

Hatchbox symlinks `storage/` to a shared directory on every deploy, so the SQLite databases in `storage/db/` survive releases with no extra configuration. **Verify this on the box before relying on it.** The `db/` and `files/` split is ours, and Hatchbox's documented default is a flat `storage/`:

```bash
readlink -f /home/deploy/<app>/current/storage
```

### Run a job worker

Solid Queue only starts inside Puma when `SOLID_QUEUE_IN_PUMA` is set. Otherwise run `bin/jobs` as a separate process, which is the better shape here, because libvips then competes with nothing for the web threads.

Without a worker, newly uploaded photos never get their variants and never appear. Tests run jobs inline, so the only real proof is attaching a photo on the box and watching it appear.

### Keep the CDN in front

With `R2_PUBLIC_HOST` set, image URLs are the bucket's own keys on the CDN domain. Without it, they fall back to the Rails proxy, and every image request reaches Puma. Rails already sends a long-lived public `Cache-Control` on variant URLs, so check that the CDN is actually caching them: fetch a derivative twice and confirm the second response comes from the edge.

Two rules follow, and both look harmless to break:

- **Never set `config.active_storage.urls_expire_in`.** An expiry makes every render emit a different URL, which means zero cache hits and a CDN full of URLs that later 404.
- **Treat `SECRET_KEY_BASE` as permanent.** It signs every image URL, so rotating it breaks every cached URL and every link anyone has shared. The one exception is a compromised key: rotate it then, and accept the cost.

### Backups

Register the primary database with Hatchbox at its **shared** absolute path, not a release path, which changes on every deploy. Hatchbox's backups cover the database only.

The photos are the thing this app exists to hold, and they need their own answer. `storage:to_r2` deliberately leaves the box's local copies in place: until something else backs the bucket up, they are the only other copy.

## Project layout

```text
app/
  controllers/        public galleries, sections, photos; sitemap; admin import
  models/             Gallery → Section → Photo, ImageMetadata (dimensions, colour, blurhash, GPS)
  avo/                admin resources
  javascript/         Stimulus: lightbox, blurhash, importer, site nav, back to top
  views/shared/       nav, footer and icons ported from friendlyrb.com
lib/tasks/            photos:ingest / preprocess / verify, storage:to_r2
public/               static error pages (self-contained), favicons
Dockerfile, compose.yaml
AGENTS.md             conventions and invariants for coding agents (CLAUDE.md includes it)
```

## License

[MIT](LICENSE)
