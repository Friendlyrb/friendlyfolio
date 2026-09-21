import { Controller } from "@hotwired/stimulus"

// Opening, stepping through and deep-linking photos. Everything the native
// <dialog> already provides -- focus trapping, Escape, the backdrop, aria-modal
// -- is deliberately not reimplemented here.
export default class extends Controller {
  static targets = ["dialog", "figure", "placeholder", "image", "avif", "counter", "download", "share2048", "tile", "manifest"]
  static values = { sectionPath: String }

  connect() {
    const data = JSON.parse(this.manifestTarget.textContent)
    this.photos = data.photos
    this.nextPage = data.nextPage
    this.prevPage = data.prevPage
    this.index = -1
    this.returnFocusTo = null

    // A shared link lands here: the server already rendered the right page, so
    // the photo is in the manifest and we just open it.
    if (data.open) {
      const i = this.photos.findIndex((p) => p.id === data.open)
      if (i >= 0) this.show(i, { push: false })
    }

    this.onPop = () => this.dialogTarget.open && this.closeSilently()
    this.closingSilently = false
    window.addEventListener("popstate", this.onPop)

    // Turbo Drive snapshots an open dialog into its page cache; it then
    // reappears, half-broken, on a back navigation.
    this.onCache = () => this.dialogTarget.open && this.dialogTarget.close()
    document.addEventListener("turbo:before-cache", this.onCache)
  }

  disconnect() {
    window.removeEventListener("popstate", this.onPop)
    document.removeEventListener("turbo:before-cache", this.onCache)
  }

  open(event) {
    const id = Number(event.currentTarget.dataset.photoId)
    const i = this.photos.findIndex((p) => p.id === id)
    if (i < 0) return // no manifest entry: let the link navigate normally

    event.preventDefault()
    this.returnFocusTo = event.currentTarget
    this.show(i)
  }

  show(i, { push = true } = {}) {
    const photo = this.photos[i]
    if (!photo) return

    this.index = i
    // Set the AVIF source before the img src, so the browser picks the
    // smaller candidate rather than starting the WebP fetch first.
    this.avifTarget.srcset = photo.avif
    this.imageTarget.src = photo.webp
    // The <img> keeps painting the previous photo until the new bytes decode,
    // so reopening on another tile flashes whatever was last open. Hold the
    // photo's box in its dominant colour until decode() says the new one is
    // ready to paint; a swap that overtakes it rejects, and that newer show()
    // reveals in its turn.
    this.placeholderTarget.style.setProperty("--r", photo.r)
    this.placeholderTarget.style.setProperty("--c", photo.color || "#222")
    this.figureTarget.classList.add("is-loading")
    this.imageTarget.decode().then(() => this.figureTarget.classList.remove("is-loading"), () => {})
    this.imageTarget.alt = photo.alt
    this.downloadTarget.href = photo.download
    this.share2048Target.href = photo.share
    this.counterTarget.textContent = `${i + 1} / ${this.photos.length}`
    this.dialogTarget.setAttribute("aria-label", `Photo ${i + 1} of ${this.photos.length}`)

    if (push) history.pushState({ photo: photo.id }, "", photo.url)
    if (!this.dialogTarget.open) this.dialogTarget.showModal()

    this.preload(i + 1)
    this.preload(i - 1)
  }

  preload(i) {
    const photo = this.photos[i]
    if (photo) new Image().src = photo.webp
  }

  next() { this.step(1) }
  prev() { this.step(-1) }

  step(delta) {
    const i = this.index + delta
    if (i >= 0 && i < this.photos.length) {
      this.show(i)
      return
    }

    // The manifest only holds this page. Past either edge, follow the
    // server-computed link into the adjacent page -- navigating to this page's
    // own first or last photo would just land on the tile already open.
    const across = delta > 0 ? this.nextPage : this.prevPage
    if (across) {
      window.location = across
      return
    }

    // No adjacent page: wrap, as the reference gallery does.
    this.show(delta > 0 ? 0 : this.photos.length - 1)
  }

  key(event) {
    if (event.key === "ArrowRight") { event.preventDefault(); this.next() }
    if (event.key === "ArrowLeft") { event.preventDefault(); this.prev() }
  }

  backdropClose(event) {
    // The dialog is opaque and the figure fills it edge to edge, so the dark
    // surround a visitor reads as the backdrop is the figure, and a test for
    // the dialog alone never fires.
    if (event.target === this.dialogTarget || event.target === this.figureTarget) this.close()
  }

  close() {
    this.dialogTarget.close()
  }

  // Fires for every close path -- button, Escape, backdrop, and popstate.
  closed() {
    // A popstate close must not push: the browser already moved us, and
    // pushing here would destroy the forward entry and strand the Back button.
    if (!this.closingSilently && this.sectionPathValue && location.pathname !== this.sectionPathValue) {
      history.pushState({}, "", this.sectionPathValue)
    }
    this.closingSilently = false
    // Browsers restore focus on a normal close, but not when the close was
    // driven by popstate, so put it back explicitly.
    if (this.returnFocusTo) {
      this.returnFocusTo.focus()
      this.returnFocusTo = null
    }
  }

  // Closes without touching history -- for when the browser moved us itself.
  closeSilently() {
    this.closingSilently = true
    this.dialogTarget.close()
  }
}
