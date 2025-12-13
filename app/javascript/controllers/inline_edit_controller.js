import { Controller } from "@hotwired/stimulus"
import { FetchRequest } from "@rails/request.js"

// Inline editable label - click label to edit
// Usage: data-controller="inline-edit"
//        data-inline-edit-url-value="/contacts/1"
//        data-inline-edit-field-value="name"
export default class extends Controller {
  static targets = ["label", "text", "input"]
  static values = {
    url: String,
    field: String,
    placeholder: { type: String, default: "Not provided" }
  }

  connect() {
    this.handleClickOutside = this.handleClickOutside.bind(this)
  }

  disconnect() {
    document.removeEventListener("click", this.handleClickOutside)
  }

  edit(event) {
    event.preventDefault()
    this.originalValue = this.inputTarget.value
    this.element.classList.add("inline-edit--editing")
    this.inputTarget.focus()
    this.inputTarget.select()

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

  cancel(event) {
    if (event) event.preventDefault()
    this.inputTarget.value = this.originalValue
    this.stopEditing()
  }

  stopEditing() {
    this.element.classList.remove("inline-edit--editing")
    document.removeEventListener("click", this.handleClickOutside)
  }

  save(event) {
    if (event) event.preventDefault()
    this.submitChange()
  }

  keydown(event) {
    if (event.key === "Enter") {
      event.preventDefault()
      this.submitChange()
    } else if (event.key === "Escape") {
      event.preventDefault()
      this.cancel()
    }
  }

  async submitChange() {
    const newValue = this.inputTarget.value.trim()

    // Don't submit if value hasn't changed
    if (newValue === this.originalValue) {
      this.stopEditing()
      return
    }

    this.element.classList.add("inline-edit--saving")

    try {
      const request = new FetchRequest("PATCH", this.urlValue, {
        body: JSON.stringify({ [this.fieldValue]: newValue }),
        responseKind: "turbo-stream"
      })

      const response = await request.perform()

      if (response.ok) {
        this.updateLabel(newValue)
        this.originalValue = newValue
        this.stopEditing()
      } else {
        let errorMessage = "Failed to save changes"
        if (response.contentType?.includes("json")) {
          const json = await response.json
          errorMessage = json.error || errorMessage
        }
        alert(errorMessage)
      }
    } catch (error) {
      console.error("Save failed:", error)
      alert("Failed to save changes: " + error.message)
    } finally {
      this.element.classList.remove("inline-edit--saving")
    }
  }

  updateLabel(value) {
    if (value) {
      this.textTarget.textContent = value
      this.textTarget.classList.remove("txt-subtle")
    } else {
      this.textTarget.textContent = this.placeholderValue
      this.textTarget.classList.add("txt-subtle")
    }
  }
}
