import { Controller } from "@hotwired/stimulus"

// The friendlyrb.com nav, ported from its site.js: lifts the card once the
// page scrolls, points aria-current at the section in view, and below 64rem
// folds the links behind a Menu button.
export default class extends Controller {
  static targets = ["card", "toggle", "links"]

  connect() {
    this.sectionLinks = [...this.element.querySelectorAll("[data-section-link]")]
      .map((link) => ({ link, section: document.getElementById(link.hash.slice(1)) }))
      .filter((entry) => entry.section)
    this.current = null
    this.ticking = false

    this.onScroll = () => {
      if (this.ticking) return
      this.ticking = true
      requestAnimationFrame(() => {
        this.ticking = false
        this.update()
      })
    }
    window.addEventListener("scroll", this.onScroll, { passive: true })
    this.update()

    this.linksTarget.querySelectorAll(":scope > li").forEach((item, index) => item.style.setProperty("--i", index))
    this.element.classList.add("has-menu")
    this.toggleTarget.hidden = false

    this.onKey = (event) => {
      if (event.key === "Escape" && this.isOpen) {
        this.setOpen(false)
        this.toggleTarget.focus()
      }
    }
    this.onOutside = (event) => {
      if (!this.cardTarget.contains(event.target)) this.setOpen(false)
    }
    this.desktop = window.matchMedia("(min-width: 64rem)")
    this.onDesktop = () => this.setOpen(false)
    document.addEventListener("keydown", this.onKey)
    document.addEventListener("click", this.onOutside)
    this.desktop.addEventListener("change", this.onDesktop)
  }

  disconnect() {
    window.removeEventListener("scroll", this.onScroll)
    document.removeEventListener("keydown", this.onKey)
    document.removeEventListener("click", this.onOutside)
    this.desktop.removeEventListener("change", this.onDesktop)
  }

  get isOpen() {
    return this.element.classList.contains("is-open")
  }

  toggle() {
    this.setOpen(!this.isOpen)
  }

  // Following a link closes the menu, so an in-page jump is not hidden under it.
  linksTargetConnected(element) {
    element.addEventListener("click", (event) => {
      if (event.target.closest("a")) this.setOpen(false)
    })
  }

  // The nav keeps its closed height while open, so the list drops over the
  // page instead of pushing it down.
  setOpen(open) {
    this.element.style.height = open ? `${this.element.offsetHeight}px` : ""
    this.element.classList.toggle("is-open", open)
    this.toggleTarget.setAttribute("aria-expanded", open)
  }

  update() {
    this.element.classList.toggle("is-stuck", window.scrollY > 4)
    if (!this.sectionLinks.length) return

    // The current section is the last one whose top has passed a line a third
    // down the screen. At the very bottom of the page, the last section wins
    // even if it is short.
    const line = this.element.offsetHeight + window.innerHeight / 3
    const atBottom = window.innerHeight + window.scrollY >= document.documentElement.scrollHeight - 2
    let active = null
    this.sectionLinks.forEach((entry) => {
      if (entry.section.getBoundingClientRect().top <= line) active = entry.link
    })
    if (atBottom) active = this.sectionLinks[this.sectionLinks.length - 1].link

    if (active !== this.current) {
      this.current?.removeAttribute("aria-current")
      active?.setAttribute("aria-current", "location")
      this.current = active
    }
  }
}
