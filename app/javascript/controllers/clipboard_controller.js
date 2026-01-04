import { Controller } from "@hotwired/stimulus"

// Copy to clipboard controller
// Usage: data-controller="clipboard"
//        data-clipboard-target="source" on the element containing text to copy
//        data-clipboard-target="button" on the button (optional)
//        data-clipboard-target="label" on the button's label span
//        data-clipboard-target="icon" on the copy icon (optional)
//        data-clipboard-target="checkIcon" on the check icon (optional)
//        data-action="clipboard#copy" on the button
export default class extends Controller {
  static targets = ["source", "button", "label", "icon", "checkIcon"]

  async copy(event) {
    event.preventDefault()

    const text = this.sourceTarget.textContent.trim()

    try {
      await navigator.clipboard.writeText(text)
      this.showCopiedFeedback()
    } catch (_error) {
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
    // Update label text
    if (this.hasLabelTarget) {
      this.originalText = this.originalText || this.labelTarget.textContent
      this.labelTarget.textContent = this.labelTarget.dataset.copiedText || "Copied!"
    }

    // Swap icons
    if (this.hasIconTarget && this.hasCheckIconTarget) {
      this.iconTarget.classList.add("hidden")
      this.checkIconTarget.classList.remove("hidden")
    }

    // Add success state to button
    if (this.hasButtonTarget) {
      this.buttonTarget.classList.add("copied")
    }

    setTimeout(() => {
      if (this.hasLabelTarget) {
        this.labelTarget.textContent = this.originalText
      }
      if (this.hasIconTarget && this.hasCheckIconTarget) {
        this.iconTarget.classList.remove("hidden")
        this.checkIconTarget.classList.add("hidden")
      }
      if (this.hasButtonTarget) {
        this.buttonTarget.classList.remove("copied")
      }
    }, 2000)
  }
}
