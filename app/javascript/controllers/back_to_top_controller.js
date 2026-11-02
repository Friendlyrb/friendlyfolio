import { Controller } from "@hotwired/stimulus"

// The friendlyrb.com back-to-top button: shows once the page has scrolled a
// screen or so, which on a 300-photo wall is most of the visit.
export default class extends Controller {
  connect() {
    this.ticking = false
    this.onScroll = () => {
      if (this.ticking) return
      this.ticking = true
      requestAnimationFrame(() => {
        this.ticking = false
        this.element.classList.toggle("is-visible", window.scrollY > 600)
      })
    }
    window.addEventListener("scroll", this.onScroll, { passive: true })
    this.onScroll()
  }

  disconnect() {
    window.removeEventListener("scroll", this.onScroll)
  }

  scroll() {
    window.scrollTo({ top: 0, behavior: window.matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth" })
    document.getElementById("main")?.focus({ preventScroll: true })
  }
}
