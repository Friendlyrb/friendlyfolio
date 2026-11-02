import { Controller } from "@hotwired/stimulus"

// The pointer drift of friendlyrb.com's hero: sets --px and --py (-1 to 1)
// from the pointer's position over the element, and the stylesheet moves the
// pile and the loose pixels by their own depth. Only for a fine pointer, and
// not at all with reduced motion.
export default class extends Controller {
  connect() {
    const fine = window.matchMedia("(pointer: fine)").matches
    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches
    if (!fine || reduced) return

    this.onMove = (event) => {
      if (this.frame) return
      this.frame = requestAnimationFrame(() => {
        this.frame = null
        const box = this.element.getBoundingClientRect()
        const x = ((event.clientX - box.left) / box.width) * 2 - 1
        const y = ((event.clientY - box.top) / box.height) * 2 - 1
        this.element.style.setProperty("--px", Math.max(-1, Math.min(1, x)).toFixed(3))
        this.element.style.setProperty("--py", Math.max(-1, Math.min(1, y)).toFixed(3))
      })
    }
    this.onLeave = () => {
      this.element.style.setProperty("--px", 0)
      this.element.style.setProperty("--py", 0)
    }
    this.element.addEventListener("pointermove", this.onMove)
    this.element.addEventListener("pointerleave", this.onLeave)
  }

  disconnect() {
    if (!this.onMove) return
    cancelAnimationFrame(this.frame)
    this.element.removeEventListener("pointermove", this.onMove)
    this.element.removeEventListener("pointerleave", this.onLeave)
  }
}
