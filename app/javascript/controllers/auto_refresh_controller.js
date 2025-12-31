import { Controller } from "@hotwired/stimulus"

// Auto-refresh controller - refreshes the parent turbo-frame periodically
// Usage: data-controller="auto-refresh"
//        data-auto-refresh-url-value="/path/to/refresh"
//        data-auto-refresh-interval-value="3000" (ms, default 3000)
export default class extends Controller {
  static values = {
    url: String,
    interval: { type: Number, default: 3000 }
  }

  connect() {
    this.timer = setTimeout(() => this.refresh(), this.intervalValue)
  }

  disconnect() {
    if (this.timer) {
      clearTimeout(this.timer)
    }
  }

  refresh() {
    const frame = this.element.closest("turbo-frame")
    if (frame && this.urlValue) {
      frame.src = this.urlValue + "?_t=" + Date.now()
    }
  }
}
