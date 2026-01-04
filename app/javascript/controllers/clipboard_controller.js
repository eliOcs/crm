import { Controller } from "@hotwired/stimulus"

// Copy to clipboard controller
// Usage: data-controller="clipboard"
//        data-clipboard-target="source" on the element containing text to copy
//        data-clipboard-target="button" on the button (optional)
//        data-clipboard-target="label" on the button's label span
//        data-action="clipboard#copy" on the button
export default class extends Controller {
  static targets = ["source", "button", "label"]

  async copy(event) {
    event.preventDefault()

    const text = this.sourceTarget.textContent.trim()

    try {
      await navigator.clipboard.writeText(text)
      this.showCopiedFeedback()
    } catch (error) {
      // Fallback for older browsers
      this.fallbackCopy(text)
    }
  }

  fallbackCopy(text) {
    const textarea = document.createElement("textarea")
    textarea.value = text
    textarea.style.position = "fixed"
    textarea.style.opacity = "0"
    document.body.appendChild(textarea)
    textarea.select()
    document.execCommand("copy")
    document.body.removeChild(textarea)
    this.showCopiedFeedback()
  }

  showCopiedFeedback() {
    if (!this.hasLabelTarget) return

    const originalText = this.labelTarget.textContent
    this.labelTarget.textContent = this.labelTarget.dataset.copiedText || "Copied!"

    if (this.hasButtonTarget) {
      this.buttonTarget.classList.add("btn--success")
    }

    setTimeout(() => {
      this.labelTarget.textContent = originalText
      if (this.hasButtonTarget) {
        this.buttonTarget.classList.remove("btn--success")
      }
    }, 2000)
  }
}
