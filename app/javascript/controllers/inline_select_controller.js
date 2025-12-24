import { Controller } from "@hotwired/stimulus"
import { FetchRequest } from "@rails/request.js"

// Inline editable select using customizable native select (appearance: base-select)
// Usage: data-controller="inline-select"
//        data-inline-select-url-value="/tasks/1"
//        data-inline-select-field-value="status"
//        data-action="change->inline-select#select"
export default class extends Controller {
  static values = {
    url: String,
    field: String
  }

  async select(event) {
    const newValue = this.element.value
    const previousValue = this.element.dataset.previousValue || ""

    // Store current value for potential rollback
    if (!this.element.dataset.previousValue) {
      this.element.dataset.previousValue = previousValue
    }

    // Don't submit if value hasn't changed
    if (newValue === previousValue) {
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
        // Update stored previous value
        this.element.dataset.previousValue = newValue
      } else {
        // Rollback on error
        this.element.value = previousValue
        let errorMessage = "Failed to save changes"
        if (response.contentType?.includes("json")) {
          const json = await response.json
          errorMessage = json.error || errorMessage
        }
        alert(errorMessage)
      }
    } catch (error) {
      // Rollback on error
      this.element.value = previousValue
      console.error("Save failed:", error)
      alert("Failed to save changes: " + error.message)
    } finally {
      this.element.classList.remove("inline-select--saving")
    }
  }

  connect() {
    // Store initial value for rollback capability
    this.element.dataset.previousValue = this.element.value
  }
}
