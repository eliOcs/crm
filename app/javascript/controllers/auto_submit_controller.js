import { Controller } from "@hotwired/stimulus"

// Auto-submit form controller
// Usage: data-controller="auto-submit"
//        data-action="change->auto-submit#submit" on form inputs
export default class extends Controller {
  submit() {
    this.element.requestSubmit()
  }
}
