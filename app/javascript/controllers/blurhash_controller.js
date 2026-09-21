import { Controller } from "@hotwired/stimulus"
import { decode } from "blurhash"

// Paints a photo's blurhash behind it as a background image, so a lazily
// loaded tile blurs in rather than appearing over a flat colour.
//
// One controller on the container rather than one per photo -- a section holds
// up to 300 -- and an observer rather than a loop over all of them on connect:
// decoding every tile up front is work nobody scrolls far enough to see, and
// toDataURL is not free at that count. The 200px margin paints a tile just
// before the browser reaches its lazy <img>.
export default class extends Controller {
  connect() {
    this.observer = new IntersectionObserver((entries) => this.paintVisible(entries), { rootMargin: "200px" })
    this.element.querySelectorAll("[data-blurhash]").forEach((el) => this.observer.observe(el))
  }

  disconnect() {
    this.observer.disconnect()
  }

  paintVisible(entries) {
    for (const { target, isIntersecting } of entries) {
      if (!isIntersecting) continue
      this.observer.unobserve(target)
      this.paint(target)
    }
  }

  paint(el) {
    // Nothing to blur in: the photo is already on screen.
    if (el.querySelector("img")?.complete) return

    // --r is the tile's stored aspect ratio. The gallery card has none and is
    // 3/2 by stylesheet, which is what the fallback is.
    const r = parseFloat(el.style.getPropertyValue("--r")) || 1.5
    const w = 32
    const h = Math.max(1, Math.round(w / r))

    const canvas = document.createElement("canvas")
    canvas.width = w
    canvas.height = h
    canvas.getContext("2d").putImageData(new ImageData(decode(el.dataset.blurhash, w, h), w, h), 0, 0)

    // A background rather than an element: the <img> paints over it when it
    // arrives, so there is nothing to hide, swap or clean up afterwards.
    el.style.backgroundImage = `url("${canvas.toDataURL()}")`
    el.style.backgroundSize = "cover"
  }
}
