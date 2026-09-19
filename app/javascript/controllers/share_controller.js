import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["label"]

  // writeText must be called synchronously inside the gesture handler: an await
  // before it loses transient activation in Safari and throws.
  copy() {
    const url = window.location.href

    if (navigator.share && navigator.maxTouchPoints > 0) {
      navigator.share({ url }).catch(() => this.writeClipboard(url))
      return
    }

    this.writeClipboard(url)
  }

  writeClipboard(url) {
    navigator.clipboard.writeText(url).then(
      () => this.confirm("Copied"),
      () => this.reveal(url)
    )
  }

  confirm(text) {
    const original = this.labelTarget.textContent
    this.labelTarget.textContent = text
    setTimeout(() => { this.labelTarget.textContent = original }, 1500)
  }

  // Clipboard refused: show the URL pre-selected so it can be copied manually.
  reveal(url) {
    const input = document.createElement("input")
    input.readOnly = true
    input.value = url
    input.className = "share-fallback"
    this.element.after(input)
    input.select()
  }
}
