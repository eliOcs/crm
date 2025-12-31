import { Controller } from "@hotwired/stimulus"

// Polling controller - periodically reloads a Turbo Frame
// Usage: data-controller="polling"
//        data-polling-interval-value="5000" (optional, default 5000ms)
//        data-polling-active-value="true" (optional, default true)
//        data-polling-frame-value="frame-id" (optional, finds frame by ID)
export default class extends Controller {
  static values = {
    interval: { type: Number, default: 5000 },
    active: { type: Boolean, default: true },
    frame: { type: String, default: "" }
  }

  connect() {
    if (this.activeValue) {
      this.startPolling()
    }
  }

  disconnect() {
    this.stopPolling()
  }

  startPolling() {
    // Initial poll after short delay
    this.timer = setInterval(() => {
      this.reload()
    }, this.intervalValue)
  }

  stopPolling() {
    if (this.timer) {
      clearInterval(this.timer)
      this.timer = null
    }
  }

  activeValueChanged() {
    if (this.activeValue) {
      this.startPolling()
    } else {
      this.stopPolling()
    }
  }

  reload() {
    const frame = this.findFrame()
    if (!frame) return

    // Get the base URL without any cache-busting params
    const url = new URL(frame.src || frame.dataset.src, window.location.origin)
    url.searchParams.set("_t", Date.now())
    frame.src = url.toString()
  }

  findFrame() {
    if (this.frameValue) {
      return document.getElementById(this.frameValue)
    }
    return this.element.querySelector("turbo-frame") || this.element.closest("turbo-frame")
  }
}
