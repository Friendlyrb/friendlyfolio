import { Controller } from "@hotwired/stimulus"

// Opening, stepping through and deep-linking photos. Everything the native
// <dialog> already provides -- focus trapping, Escape, the backdrop, aria-modal
// -- is deliberately not reimplemented here.
export default class extends Controller {
  static targets = ["dialog", "image", "counter", "download", "share2048", "tile", "manifest"]
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
    this.imageTarget.src = photo.webp
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
    if (event.target === this.dialogTarget) this.close()
  }

  close() {
    this.dialogTarget.close()
  }

  // Fires for every close path -- button, Escape, backdrop.
  closed() {
    if (this.sectionPathValue && location.pathname !== this.sectionPathValue) {
      history.pushState({}, "", this.sectionPathValue)
    }
    // Browsers restore focus on a normal close, but not when the close was
    // driven by popstate, so put it back explicitly.
    if (this.returnFocusTo) {
      this.returnFocusTo.focus()
      this.returnFocusTo = null
    }
  }

  closeSilently() {
    this.dialogTarget.close()
  }
}
