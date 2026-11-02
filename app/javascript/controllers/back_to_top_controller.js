import { Controller } from "@hotwired/stimulus"

// The friendlyrb.com back-to-top button. It shows past 600px there, but every
// page on that site is long; here the index and sign-in scroll less than 600px
// in total, so a fixed threshold meant the button never appeared on them. A
// shorter page shows it halfway down instead, and a page that barely scrolls
// has no top to get back to.
const THRESHOLD = 600
const MIN_SCROLL = 200

export default class extends Controller {
  connect() {
    this.ticking = false
    this.onScroll = () => {
      if (this.ticking) return
      this.ticking = true
      requestAnimationFrame(() => {
        this.ticking = false
        // Measured on every scroll: lazily loaded sections grow the page.
        const room = document.documentElement.scrollHeight - window.innerHeight
        const threshold = Math.min(THRESHOLD, room / 2)
        this.element.classList.toggle("is-visible", room > MIN_SCROLL && window.scrollY > threshold)
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
    // As on friendlyrb.com: keyboard focus lands on the first link at the top,
    // not left behind at the bottom of the page.
    document.querySelector("nav a, main a")?.focus({ preventScroll: true })
  }
}
