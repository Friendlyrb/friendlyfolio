import { Controller } from "@hotwired/stimulus"

// A flash card: closes on its button, and a notice also closes itself after a
// few seconds. Alerts get no timer -- an error should not vanish before it has
// been read. Hovering or focusing the card pauses the timer for the same reason.
export default class extends Controller {
  static values = { dismissAfter: Number }

  connect() {
    if (!this.dismissAfterValue) return

    this.start = () => { this.timer = setTimeout(() => this.dismiss(), this.dismissAfterValue) }
    this.pause = () => clearTimeout(this.timer)
    this.element.addEventListener("mouseenter", this.pause)
    this.element.addEventListener("mouseleave", this.start)
    this.element.addEventListener("focusin", this.pause)
    this.element.addEventListener("focusout", this.start)
    this.start()
  }

  disconnect() {
    clearTimeout(this.timer)
  }

  dismiss() {
    clearTimeout(this.timer)
    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches
    if (reduced) return this.remove()

    this.element.classList.add("is-leaving")
    this.element.addEventListener("transitionend", () => this.remove(), { once: true })
    // A close during the entrance animation runs no transition -- the
    // animation owns opacity and translate -- so transitionend never fires.
    setTimeout(() => this.remove(), 300)
  }

  remove() {
    if (!this.element.isConnected) return

    const stack = this.element.parentElement
    this.element.remove()
    if (stack && !stack.children.length) stack.remove()
  }
}
