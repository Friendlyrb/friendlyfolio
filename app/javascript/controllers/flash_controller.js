import { Controller } from "@hotwired/stimulus"

// A flash card: closes on its button, and a notice also closes itself after a
// few seconds. Alerts get no timer -- an error should not vanish before it has
// been read. Hovering or focusing the card pauses the timer for the same reason.
export default class extends Controller {
  static values = { dismissAfter: Number }

  connect() {
    if (!this.dismissAfterValue) return

    // Hover and focus hold the notice independently: leaving one must not
    // restart the timer while the other still holds it.
    this.hovering = false
    this.focused = false
    this.hold = (key, value) => {
      this[key] = value
      this.schedule()
    }
    this.onEnter = () => this.hold("hovering", true)
    this.onLeave = () => this.hold("hovering", false)
    this.onFocusIn = () => this.hold("focused", true)
    this.onFocusOut = (event) => {
      if (!this.element.contains(event.relatedTarget)) this.hold("focused", false)
    }
    this.element.addEventListener("mouseenter", this.onEnter)
    this.element.addEventListener("mouseleave", this.onLeave)
    this.element.addEventListener("focusin", this.onFocusIn)
    this.element.addEventListener("focusout", this.onFocusOut)
    this.schedule()
  }

  // Always clears the previous timer first, so repeated hovers never leave an
  // older one running.
  schedule() {
    clearTimeout(this.timer)
    if (!this.hovering && !this.focused) {
      this.timer = setTimeout(() => this.dismiss(), this.dismissAfterValue)
    }
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
