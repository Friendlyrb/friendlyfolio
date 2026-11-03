import { Controller } from "@hotwired/stimulus"

// How long a section jump keeps re-aiming at its target while the sections
// above it load. Long enough for a slow connection; a fetch that fails never
// fires turbo:frame-load, so it must not wait for ever.
const SETTLE_LIMIT = 15000

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
      // A modified or non-primary click opens the section elsewhere (a new
      // tab or window), and this page must not move; nor after another
      // handler has taken the click.
      if (event.defaultPrevented || event.button !== 0) return
      if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return
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
  // So: load every section above the target now, and aim again each time one
  // arrives, until all have. A smooth scroll in flight just bends to the new
  // position.
  //
  // The visitor's own input wins: wheel, touch, keys or any pointer press
  // (the Back to top button, a scrollbar drag) ends it, so a late arrival can
  // never pull them back down. A section that never arrives (a failed fetch)
  // gives up after SETTLE_LIMIT rather than listening forever.
  settle(target) {
    this.settling?.()
    if (!target) return

    // turbo:frame-load, not frame.loaded: for a lazy frame that has not
    // started, loaded is already resolved. A frame marked complete has its
    // real height already, so it cannot move the target.
    const pending = new Set(
      [...document.querySelectorAll("turbo-frame[src]:not([complete])")]
        .filter((frame) => target.compareDocumentPosition(frame) & Node.DOCUMENT_POSITION_PRECEDING)
    )
    if (!pending.size) return

    let frame = null
    // scrollIntoView honours the root's scroll-padding-top and, through the
    // stylesheet, smooth scrolling unless reduced motion is preferred. One
    // animation frame first, for the new wall to lay out.
    const aim = () => {
      cancelAnimationFrame(frame)
      frame = requestAnimationFrame(() => target.scrollIntoView({ block: "start" }))
    }
    const onLoad = (event) => {
      pending.delete(event.target)
      aim()
      if (!pending.size) finish()
    }
    const stopOn = ["wheel", "touchstart", "keydown", "pointerdown"]
    const finish = () => {
      clearTimeout(limit)
      stopOn.forEach((type) => window.removeEventListener(type, cancel, true))
      pending.forEach((section) => section.removeEventListener("turbo:frame-load", onLoad))
      if (this.settling === cancel) this.settling = null
    }
    const cancel = () => {
      cancelAnimationFrame(frame)
      finish()
    }
    const limit = setTimeout(finish, SETTLE_LIMIT)

    stopOn.forEach((type) => window.addEventListener(type, cancel, { capture: true, passive: true }))
    pending.forEach((section) => {
      section.addEventListener("turbo:frame-load", onLoad)
      section.setAttribute("loading", "eager")
    })
    this.settling = cancel
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
