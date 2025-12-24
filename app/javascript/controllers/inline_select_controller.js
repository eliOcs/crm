import { Controller } from "@hotwired/stimulus"
import { FetchRequest } from "@rails/request.js"

// Inline editable select - click badge to show dropdown, auto-saves on change
// Usage: data-controller="inline-select"
//        data-inline-select-url-value="/tasks/1"
//        data-inline-select-field-value="status"
export default class extends Controller {
  static targets = ["badge", "select"]
  static values = {
    url: String,
    field: String
  }

  connect() {
    this.handleClickOutside = this.handleClickOutside.bind(this)
  }

  disconnect() {
    document.removeEventListener("click", this.handleClickOutside)
  }

  edit(event) {
    event.preventDefault()
    event.stopPropagation()
    this.originalValue = this.selectTarget.value
    this.element.classList.add("inline-select--editing")
    this.selectTarget.focus()

    // Listen for clicks outside to cancel
    setTimeout(() => {
      document.addEventListener("click", this.handleClickOutside)
    }, 0)
  }

  handleClickOutside(event) {
    if (!this.element.contains(event.target)) {
      this.cancel()
    }
  }

  cancel() {
    this.selectTarget.value = this.originalValue
    this.stopEditing()
  }

  stopEditing() {
    this.element.classList.remove("inline-select--editing")
    document.removeEventListener("click", this.handleClickOutside)
  }

  async change(event) {
    const newValue = event.target.value

    // Don't submit if value hasn't changed
    if (newValue === this.originalValue) {
      this.stopEditing()
      return
    }

    this.element.classList.add("inline-select--saving")

    try {
      const request = new FetchRequest("PATCH", this.urlValue, {
        body: JSON.stringify({ [this.fieldValue]: newValue }),
        responseKind: "turbo-stream"
      })

      const response = await request.perform()

      if (response.ok) {
        this.updateBadge(newValue)
        this.originalValue = newValue
        this.stopEditing()
      } else {
        let errorMessage = "Failed to save changes"
        if (response.contentType?.includes("json")) {
          const json = await response.json
          errorMessage = json.error || errorMessage
        }
        alert(errorMessage)
        this.selectTarget.value = this.originalValue
      }
    } catch (error) {
      console.error("Save failed:", error)
      alert("Failed to save changes: " + error.message)
      this.selectTarget.value = this.originalValue
    } finally {
      this.element.classList.remove("inline-select--saving")
    }
  }

  updateBadge(value) {
    const selectedOption = this.selectTarget.options[this.selectTarget.selectedIndex]
    const label = selectedOption.text

    // Update badge text and class (preserve inline-select__badge for CSS)
    this.badgeTarget.textContent = label
    this.badgeTarget.className = `inline-select__badge status-badge status-badge--${value}`
  }

  keydown(event) {
    if (event.key === "Escape") {
      event.preventDefault()
      this.cancel()
    }
  }
}
