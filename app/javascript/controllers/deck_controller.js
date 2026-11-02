import { Controller } from "@hotwired/stimulus"

// Deals the index's pile of polaroids: every few seconds the top photo slides
// off to the side and tucks under the pile, and the next one is on top.
//
// It is a carousel, so it can be stopped (WCAG 2.2.2): a Pause button, and it
// holds still while pointed at, while anything in it has focus, and while the
// tab is hidden. With reduced motion it starts paused, and dealing by hand
// skips the slide.
export default class extends Controller {
  static targets = ["card", "toggle"]
  static values = { interval: { type: Number, default: 4500 } }

  connect() {
    this.order = [...this.cardTargets]
    if (this.order.length < 2) return

    this.reduced = window.matchMedia("(prefers-reduced-motion: reduce)")
    this.paused = this.reduced.matches
    this.hovering = false
    this.focused = false

    this.onEnter = () => { this.hovering = true; this.schedule() }
    this.onLeave = () => { this.hovering = false; this.schedule() }
    this.onFocusIn = () => { this.focused = true; this.schedule() }
    this.onFocusOut = (event) => {
      if (this.element.contains(event.relatedTarget)) return
      this.focused = false
      this.schedule()
    }
    this.onVisibility = () => this.schedule()
    this.element.addEventListener("pointerenter", this.onEnter)
    this.element.addEventListener("pointerleave", this.onLeave)
    this.element.addEventListener("focusin", this.onFocusIn)
    this.element.addEventListener("focusout", this.onFocusOut)
    document.addEventListener("visibilitychange", this.onVisibility)

    this.toggleTarget.hidden = false
    this.element.classList.add("is-live")
    this.render()
    this.schedule()
  }

  disconnect() {
    this.element.classList.remove("is-live")
    clearTimeout(this.timer)
    clearTimeout(this.fallback)
    if (!this.onEnter) return
    this.element.removeEventListener("pointerenter", this.onEnter)
    this.element.removeEventListener("pointerleave", this.onLeave)
    this.element.removeEventListener("focusin", this.onFocusIn)
    this.element.removeEventListener("focusout", this.onFocusOut)
    document.removeEventListener("visibilitychange", this.onVisibility)
  }

  get running() {
    return !this.paused && !this.hovering && !this.focused && !document.hidden
  }

  toggle() {
    this.paused = !this.paused
    this.render()
    this.schedule()
  }

  schedule() {
    clearTimeout(this.timer)
    if (this.running) this.timer = setTimeout(() => this.deal(), this.intervalValue)
  }

  deal() {
    const top = this.order[0]
    let done = false
    const finish = () => {
      if (done) return
      done = true
      clearTimeout(this.fallback)
      top.classList.remove("is-dealt")
      this.order.push(this.order.shift())
      this.render()
      this.schedule()
    }

    if (this.reduced.matches) return finish()

    top.classList.add("is-dealt")
    top.addEventListener("animationend", finish, { once: true })
    // In case the animation never runs (a background tab, a style override).
    this.fallback = setTimeout(finish, 1500)
  }

  // Stacking order, which cards show, and which one can take focus: only the
  // top photo is a live link, the rest are underneath it.
  render() {
    const count = this.order.length
    this.order.forEach((card, depth) => {
      card.dataset.depth = depth
      card.style.setProperty("--z", count - depth)
      card.inert = depth !== 0
    })
    // The button's label says what it will do (Pause / Play), so it carries
    // no aria-pressed as well: both together read as contradictory states.
    this.element.classList.toggle("is-paused", this.paused)
  }
}
