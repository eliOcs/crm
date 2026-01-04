import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static values = {
    duration: { type: Number, default: 4000 },
  };

  connect() {
    this.timeout = setTimeout(() => this.dismiss(), this.durationValue);
  }

  disconnect() {
    if (this.timeout) {
      clearTimeout(this.timeout);
    }
  }

  dismiss() {
    this.element.classList.add("toast--exiting");
    this.element.addEventListener(
      "animationend",
      () => {
        this.element.remove();
      },
      { once: true },
    );
  }
}
