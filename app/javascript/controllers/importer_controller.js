import { Controller } from "@hotwired/stimulus"
import { DirectUpload } from "@rails/activestorage"

const IMAGE = /\.(jpe?g|png|webp|avif|tiff?|heic|heif)$/i
// Bounded: the browser will happily open hundreds of sockets, and the server
// is about to bake every one of these.
const CONCURRENCY = 4

export default class extends Controller {
  static targets = ["drop", "input", "status", "plan", "start", "gallery"]
  static values = { url: String, directUploadUrl: String }

  connect() {
    this.files = []
  }

  over(event) {
    event.preventDefault()
    this.dropTarget.classList.add("is-over")
  }

  leave() {
    this.dropTarget.classList.remove("is-over")
  }

  async drop(event) {
    event.preventDefault()
    this.leave()
    this.setStatus("Reading folder…")

    // A dropped directory only yields its contents through the entry API;
    // DataTransfer.files alone gives you the folder and nothing inside it.
    const entries = [...event.dataTransfer.items]
      .map((item) => item.webkitGetAsEntry())
      .filter(Boolean)

    const found = []
    for (const entry of entries) await this.walk(entry, "", found)
    this.propose(found)
  }

  picked(event) {
    // webkitdirectory gives each file a relative path already.
    const found = [...event.target.files]
      .filter((file) => IMAGE.test(file.name))
      .map((file) => ({ file, path: file.webkitRelativePath || file.name }))
    this.propose(found)
  }

  async walk(entry, prefix, found) {
    if (entry.isFile) {
      if (!IMAGE.test(entry.name)) return
      const file = await new Promise((resolve) => entry.file(resolve))
      found.push({ file, path: prefix + entry.name })
      return
    }

    // readEntries returns at most 100 per call, so it has to be drained.
    const reader = entry.createReader()
    for (;;) {
      const batch = await new Promise((resolve) => reader.readEntries(resolve))
      if (!batch.length) break
      for (const child of batch) await this.walk(child, `${prefix}${entry.name}/`, found)
    }
  }

  propose(found) {
    this.files = found
    if (!found.length) {
      this.setStatus("No images found in that folder.")
      this.startTarget.hidden = true
      return
    }

    const bySection = this.groupBySection(found)
    this.planTarget.innerHTML = [...bySection.entries()]
      .map(([section, files]) => `<li><strong>${section}</strong> — ${files.length} photo${files.length === 1 ? "" : "s"}</li>`)
      .join("")

    this.setStatus(`${found.length} photos ready.`)
    this.startTarget.hidden = false
  }

  // The first path segment is the section; a loose file has none.
  groupBySection(found) {
    const groups = new Map()
    for (const item of found) {
      const parts = item.path.split("/")
      const section = parts.length > 1 ? parts[parts.length - 2] : "photos"
      if (!groups.has(section)) groups.set(section, [])
      groups.get(section).push(item)
    }
    return groups
  }

  async start() {
    this.startTarget.hidden = true
    this.inputTarget.disabled = true

    const queue = [...this.files]
    const total = queue.length
    const result = { imported: 0, skipped: 0, rejected: 0, failed: 0 }
    const rejected = []

    const worker = async () => {
      for (;;) {
        const item = queue.shift()
        if (!item) return
        const outcome = await this.upload(item)
        result[outcome.status] = (result[outcome.status] || 0) + 1
        if (outcome.status === "rejected") rejected.push(`${item.path} — ${outcome.reason}`)
        this.setStatus(`${result.imported + result.skipped + result.rejected + result.failed} of ${total}…`)
      }
    }

    await Promise.all(Array.from({ length: CONCURRENCY }, worker))
    this.report(result, rejected)
  }

  upload(item) {
    return new Promise((resolve) => {
      const upload = new DirectUpload(item.file, this.directUploadUrlValue)
      upload.create((error, blob) => {
        if (error) return resolve({ status: "failed", reason: error })
        resolve(this.register(item, blob))
      })
    })
  }

  async register(item, blob) {
    const parts = item.path.split("/")
    const body = new FormData()
    body.append("gallery_slug", this.galleryTarget.value)
    body.append("section_slug", parts.length > 1 ? parts[parts.length - 2] : "photos")
    body.append("filename", item.file.name)
    body.append("signed_id", blob.signed_id)

    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        body,
        headers: { "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content || "" }
      })
      return await response.json()
    } catch (error) {
      return { status: "failed", reason: String(error) }
    }
  }

  report(result, rejected) {
    const parts = [`${result.imported} imported`]
    if (result.skipped) parts.push(`${result.skipped} already there`)
    if (result.rejected) parts.push(`${result.rejected} rejected`)
    if (result.failed) parts.push(`${result.failed} failed`)

    this.setStatus(`${parts.join(", ")}. Derivatives are baking in the background — the photos appear once they finish.`)

    if (rejected.length) {
      this.planTarget.innerHTML +=
        `<li class="importer__rejected"><strong>Rejected:</strong><br>${rejected.join("<br>")}</li>`
    }
    this.inputTarget.disabled = false
  }

  setStatus(text) {
    this.statusTarget.textContent = text
  }
}
