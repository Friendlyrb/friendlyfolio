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
    this.onSectionClick = (event) => {
      const link = event.target.closest("[data-section-link]")
      if (link) this.settle(document.getElementById(link.hash.slice(1)))
    }
    this.element.addEventListener("click", this.onSectionClick)

    this.desktop = window.matchMedia("(min-width: 64rem)")
    this.onDesktop = () => this.setOpen(false)
    document.addEventListener("keydown", this.onKey)
    document.addEventListener("click", this.onOutside)
    this.desktop.addEventListener("change", this.onDesktop)
  }

  disconnect() {
    this.settling?.()
    this.element.removeEventListener("click", this.onSectionClick)
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

  // The browser scrolls to where the section is when the link is clicked.
  // But every section after the first loads lazily, and as the scroll passes
  // them their real walls replace a reserved height -- usually taller -- so
  // the target moves after it was aimed at and the scroll lands far short.
  // So: load every section above the target now, then aim again once they
  // have arrived. A smooth scroll in flight just bends to the new position.
  // Any scrolling of the visitor's own in the meantime wins.
  async settle(target) {
    if (!target) return

    this.settling?.()
    let cancelled = false
    const cancel = () => { cancelled = true }
    const stopOn = ["wheel", "touchstart", "keydown"]
    stopOn.forEach((type) => window.addEventListener(type, cancel, { passive: true, once: true }))
    this.settling = () => {
      cancel()
      stopOn.forEach((type) => window.removeEventListener(type, cancel))
    }

    // Waits on turbo:frame-load rather than frame.loaded: for a lazy frame
    // that has not started, loaded is already resolved, so it waited for
    // nothing. A frame marked complete has its real height already.
    const pending = [...document.querySelectorAll("turbo-frame[src]:not([complete])")]
      .filter((frame) => target.compareDocumentPosition(frame) & Node.DOCUMENT_POSITION_PRECEDING)
    const arrived = pending.map((frame) => new Promise((resolve) => {
      frame.addEventListener("turbo:frame-load", resolve, { once: true })
    }))
    pending.forEach((frame) => frame.setAttribute("loading", "eager"))
    await Promise.race([
      Promise.all(arrived),
      new Promise((resolve) => setTimeout(resolve, 4000))
    ])
    // One frame for the new walls to lay out before measuring again.
    await new Promise((resolve) => requestAnimationFrame(resolve))

    if (cancelled) return
    this.settling()
    this.settling = null
    // scrollIntoView honours the root's scroll-padding-top and, through the
    // stylesheet, smooth scrolling unless reduced motion is preferred.
    target.scrollIntoView({ block: "start" })
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
