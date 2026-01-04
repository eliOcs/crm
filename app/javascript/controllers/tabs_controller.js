import { Controller } from "@hotwired/stimulus";

// Tabs controller for switching between panels
// Usage: data-controller="tabs"
//        data-tabs-target="tab" data-tab="name" on tab buttons
//        data-tabs-target="panel" data-tab="name" on content panels
export default class extends Controller {
  static targets = ["tab", "panel"];

  switch(event) {
    const selectedTab = event.currentTarget.dataset.tab;

    // Update tab states
    this.tabTargets.forEach((tab) => {
      if (tab.dataset.tab === selectedTab) {
        tab.classList.add("forwarding-setup__tab--active");
      } else {
        tab.classList.remove("forwarding-setup__tab--active");
      }
    });

    // Update panel visibility
    this.panelTargets.forEach((panel) => {
      if (panel.dataset.tab === selectedTab) {
        panel.classList.remove("hidden");
      } else {
        panel.classList.add("hidden");
      }
    });
  }
}
