import { Controller } from "@hotwired/stimulus"
import { FetchRequest } from "@rails/request.js"

// Due Date Picker - click to open modal calendar picker
// Usage: data-controller="due-date-picker"
//        data-due-date-picker-url-value="/tasks/1"
//        data-due-date-picker-field-value="due_date"
//        data-due-date-picker-date-value="2026-01-15"
export default class extends Controller {
  static targets = ["display", "label", "icon"]
  static values = {
    url: String,
    field: { type: String, default: "due_date" },
    date: String,
    translations: Object
  }

  connect() {
    this.selectedDate = this.dateValue ? new Date(this.dateValue + "T00:00:00") : null
    this.viewingDate = this.selectedDate ? new Date(this.selectedDate) : new Date()
    this.pendingSelection = null
    this.modal = null
    this.backdrop = null

    this.handleKeydown = this.handleKeydown.bind(this)
    this.handleBackdropClick = this.handleBackdropClick.bind(this)
    this.handleModalClick = this.handleModalClick.bind(this)
  }

  disconnect() {
    this.close()
  }

  open(event) {
    event.preventDefault()
    if (this.modal) return

    this.pendingSelection = this.selectedDate ? new Date(this.selectedDate) : null
    this.viewingDate = this.selectedDate ? new Date(this.selectedDate) : new Date()

    this.renderModal()
    document.addEventListener("keydown", this.handleKeydown)
  }

  close() {
    if (this.modal) {
      this.modal.removeEventListener("click", this.handleModalClick)
      this.modal.remove()
      this.modal = null
    }
    if (this.backdrop) {
      this.backdrop.remove()
      this.backdrop = null
    }
    this.pendingSelection = null
    document.removeEventListener("keydown", this.handleKeydown)
  }

  handleKeydown(event) {
    if (event.key === "Escape") {
      event.preventDefault()
      this.close()
    }
  }

  handleBackdropClick(event) {
    if (event.target === this.backdrop) {
      this.close()
    }
  }

  // Event delegation for modal clicks (since modal is outside controller element)
  handleModalClick(event) {
    const target = event.target.closest("button")
    if (!target) return

    event.preventDefault()

    // Check for data-date (calendar day click)
    if (target.dataset.date) {
      this.pendingSelection = new Date(target.dataset.date + "T00:00:00")
      this.renderCalendars()
      this.updateSaveButton()
      return
    }

    // Check for data-action buttons
    const action = target.dataset.action
    if (!action) return

    if (action.includes("close")) this.close()
    else if (action.includes("prevMonth")) this.navigatePrevMonth()
    else if (action.includes("nextMonth")) this.navigateNextMonth()
    else if (action.includes("quickToday")) this.saveDate(new Date())
    else if (action.includes("quickTomorrow")) {
      const tomorrow = new Date()
      tomorrow.setDate(tomorrow.getDate() + 1)
      this.saveDate(tomorrow)
    }
    else if (action.includes("quickNextWeek")) {
      const nextWeek = new Date()
      nextWeek.setDate(nextWeek.getDate() + 7)
      this.saveDate(nextWeek)
    }
    else if (action.includes("remove")) this.saveDate(null)
    else if (action.includes("save") && this.pendingSelection) {
      this.saveDate(this.pendingSelection)
    }
  }

  navigatePrevMonth() {
    this.viewingDate.setMonth(this.viewingDate.getMonth() - 1)
    this.renderCalendars()
  }

  navigateNextMonth() {
    this.viewingDate.setMonth(this.viewingDate.getMonth() + 1)
    this.renderCalendars()
  }

  // Navigation
  prevMonth(event) {
    event.preventDefault()
    this.viewingDate.setMonth(this.viewingDate.getMonth() - 1)
    this.renderCalendars()
  }

  nextMonth(event) {
    event.preventDefault()
    this.viewingDate.setMonth(this.viewingDate.getMonth() + 1)
    this.renderCalendars()
  }

  // Date selection
  selectDate(event) {
    event.preventDefault()
    const dateStr = event.currentTarget.dataset.date
    this.pendingSelection = new Date(dateStr + "T00:00:00")
    this.renderCalendars()
    this.updateSaveButton()
  }

  // Quick actions - auto-save
  quickToday(event) {
    event.preventDefault()
    this.saveDate(new Date())
  }

  quickTomorrow(event) {
    event.preventDefault()
    const tomorrow = new Date()
    tomorrow.setDate(tomorrow.getDate() + 1)
    this.saveDate(tomorrow)
  }

  quickNextWeek(event) {
    event.preventDefault()
    const nextWeek = new Date()
    nextWeek.setDate(nextWeek.getDate() + 7)
    this.saveDate(nextWeek)
  }

  remove(event) {
    event.preventDefault()
    this.saveDate(null)
  }

  save(event) {
    event.preventDefault()
    if (this.pendingSelection) {
      this.saveDate(this.pendingSelection)
    }
  }

  async saveDate(date) {
    const dateStr = date ? this.formatISO(date) : null

    this.element.classList.add("due-date-picker--saving")

    try {
      const request = new FetchRequest("PATCH", this.urlValue, {
        body: JSON.stringify({ [this.fieldValue]: dateStr }),
        responseKind: "turbo-stream"
      })

      const response = await request.perform()

      if (response.ok) {
        this.selectedDate = date
        this.dateValue = dateStr || ""
        this.updateDisplay()
        this.close()
      } else {
        let errorMessage = "Failed to save due date"
        if (response.contentType?.includes("json")) {
          const json = await response.json
          errorMessage = json.error || errorMessage
        }
        alert(errorMessage)
      }
    } catch (error) {
      console.error("Save failed:", error)
      alert("Failed to save due date: " + error.message)
    } finally {
      this.element.classList.remove("due-date-picker--saving")
    }
  }

  // Update the display button after save
  updateDisplay() {
    const t = this.translationsValue
    const label = this.labelTarget
    const icon = this.iconTarget
    const display = this.displayTarget

    // Update label
    label.textContent = this.formatDisplayDate(this.selectedDate) || t.add

    // Update urgency class
    const urgency = this.getUrgency(this.selectedDate)
    display.className = "due-date"
    if (urgency) {
      display.classList.add(`due-date--${urgency}`)
    } else {
      display.classList.add("due-date--empty")
    }

    // Update icon
    icon.innerHTML = this.getIconSVG(urgency)
  }

  formatDisplayDate(date) {
    if (!date) return null

    const t = this.translationsValue
    const today = new Date()
    today.setHours(0, 0, 0, 0)

    const compareDate = new Date(date)
    compareDate.setHours(0, 0, 0, 0)

    const diffDays = Math.round((compareDate - today) / (1000 * 60 * 60 * 24))

    if (diffDays === 0) return t.today
    if (diffDays === 1) return t.tomorrow

    const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    if (date.getFullYear() === today.getFullYear()) {
      return `${months[date.getMonth()]} ${date.getDate()}`
    } else {
      return `${months[date.getMonth()]} ${date.getFullYear()}`
    }
  }

  getUrgency(date) {
    if (!date) return null

    const today = new Date()
    today.setHours(0, 0, 0, 0)

    const compareDate = new Date(date)
    compareDate.setHours(0, 0, 0, 0)

    const diffDays = Math.round((compareDate - today) / (1000 * 60 * 60 * 24))

    if (diffDays <= 0) return "urgent"
    if (diffDays === 1) return "soon"
    if (diffDays <= 7) return "week"
    return "later"
  }

  getIconSVG(urgency) {
    if (urgency === "urgent") {
      return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor">
        <path fill-rule="evenodd" d="M5.75 2a.75.75 0 0 1 .75.75V4h7V2.75a.75.75 0 0 1 1.5 0V4h.25A2.75 2.75 0 0 1 18 6.75v8.5A2.75 2.75 0 0 1 15.25 18H4.75A2.75 2.75 0 0 1 2 15.25v-8.5A2.75 2.75 0 0 1 4.75 4H5V2.75A.75.75 0 0 1 5.75 2Zm-1 5.5c-.69 0-1.25.56-1.25 1.25v6.5c0 .69.56 1.25 1.25 1.25h10.5c.69 0 1.25-.56 1.25-1.25v-6.5c0-.69-.56-1.25-1.25-1.25H4.75Z" clip-rule="evenodd" />
        <path d="M10 10a.75.75 0 0 1 .75.75v2a.75.75 0 0 1-1.5 0v-2A.75.75 0 0 1 10 10Zm0 5a.75.75 0 1 0 0-1.5.75.75 0 0 0 0 1.5Z" />
      </svg>`
    }
    return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor">
      <path fill-rule="evenodd" d="M5.75 2a.75.75 0 0 1 .75.75V4h7V2.75a.75.75 0 0 1 1.5 0V4h.25A2.75 2.75 0 0 1 18 6.75v8.5A2.75 2.75 0 0 1 15.25 18H4.75A2.75 2.75 0 0 1 2 15.25v-8.5A2.75 2.75 0 0 1 4.75 4H5V2.75A.75.75 0 0 1 5.75 2Zm-1 5.5c-.69 0-1.25.56-1.25 1.25v6.5c0 .69.56 1.25 1.25 1.25h10.5c.69 0 1.25-.56 1.25-1.25v-6.5c0-.69-.56-1.25-1.25-1.25H4.75Z" clip-rule="evenodd" />
    </svg>`
  }

  // Render modal
  renderModal() {
    const t = this.translationsValue

    // Create backdrop
    this.backdrop = document.createElement("div")
    this.backdrop.className = "due-date-picker__backdrop"
    this.backdrop.addEventListener("click", this.handleBackdropClick)
    document.body.appendChild(this.backdrop)

    // Create modal
    this.modal = document.createElement("div")
    this.modal.className = "due-date-picker__modal"
    this.modal.setAttribute("role", "dialog")
    this.modal.setAttribute("aria-modal", "true")
    this.modal.innerHTML = `
      <div class="due-date-picker__header">
        <h2 class="due-date-picker__title">${t.editTitle}</h2>
        <button type="button" class="due-date-picker__close" data-action="click->due-date-picker#close" aria-label="Close">
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor">
            <path d="M6.28 5.22a.75.75 0 00-1.06 1.06L8.94 10l-3.72 3.72a.75.75 0 101.06 1.06L10 11.06l3.72 3.72a.75.75 0 101.06-1.06L11.06 10l3.72-3.72a.75.75 0 00-1.06-1.06L10 8.94 6.28 5.22z" />
          </svg>
        </button>
      </div>
      <div class="due-date-picker__body">
        <div class="due-date-picker__calendars" data-calendars></div>
      </div>
      <div class="due-date-picker__footer">
        <div class="due-date-picker__quick-actions">
          <button type="button" class="btn btn--sm btn--ghost" data-action="click->due-date-picker#remove">${t.remove}</button>
        </div>
        <div class="due-date-picker__save-actions">
          <button type="button" class="btn btn--sm btn--secondary" data-action="click->due-date-picker#quickNextWeek">${t.nextWeek}</button>
          <button type="button" class="btn btn--sm btn--secondary" data-action="click->due-date-picker#quickTomorrow">${t.tomorrow}</button>
          <button type="button" class="btn btn--sm btn--secondary" data-action="click->due-date-picker#quickToday">${t.today}</button>
          <button type="button" class="btn btn--sm btn--primary" data-action="click->due-date-picker#save" data-save-button disabled>${t.save}</button>
        </div>
      </div>
    `
    document.body.appendChild(this.modal)

    // Use event delegation for all modal clicks
    this.modal.addEventListener("click", this.handleModalClick)

    this.renderCalendars()
  }

  renderCalendars() {
    const container = this.modal.querySelector("[data-calendars]")
    const t = this.translationsValue

    const leftMonth = new Date(this.viewingDate.getFullYear(), this.viewingDate.getMonth(), 1)
    const rightMonth = new Date(this.viewingDate.getFullYear(), this.viewingDate.getMonth() + 1, 1)

    container.innerHTML = `
      ${this.renderMonth(leftMonth, false)}
      ${this.renderMonth(rightMonth, true)}
    `
  }

  renderMonth(monthDate, showNav) {
    const t = this.translationsValue
    const year = monthDate.getFullYear()
    const month = monthDate.getMonth()
    const monthName = t.months[month]

    const navHTML = showNav ? `
      <div class="due-date-picker__nav">
        <button type="button" class="due-date-picker__nav-btn" data-action="click->due-date-picker#prevMonth" aria-label="Previous month">
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor">
            <path fill-rule="evenodd" d="M11.78 5.22a.75.75 0 0 1 0 1.06L8.06 10l3.72 3.72a.75.75 0 1 1-1.06 1.06l-4.25-4.25a.75.75 0 0 1 0-1.06l4.25-4.25a.75.75 0 0 1 1.06 0Z" clip-rule="evenodd" />
          </svg>
        </button>
        <button type="button" class="due-date-picker__nav-btn" data-action="click->due-date-picker#nextMonth" aria-label="Next month">
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor">
            <path fill-rule="evenodd" d="M8.22 5.22a.75.75 0 0 1 1.06 0l4.25 4.25a.75.75 0 0 1 0 1.06l-4.25 4.25a.75.75 0 0 1-1.06-1.06L11.94 10 8.22 6.28a.75.75 0 0 1 0-1.06Z" clip-rule="evenodd" />
          </svg>
        </button>
      </div>
    ` : ""

    return `
      <div class="due-date-picker__month">
        <div class="due-date-picker__month-header">
          <span class="due-date-picker__month-title">${monthName} ${year}</span>
          ${navHTML}
        </div>
        <div class="due-date-picker__weekdays">
          ${t.weekdays.map(d => `<span class="due-date-picker__weekday">${d}</span>`).join("")}
        </div>
        <div class="due-date-picker__grid">
          ${this.renderDays(year, month)}
        </div>
      </div>
    `
  }

  renderDays(year, month) {
    const days = []
    const firstDay = new Date(year, month, 1)
    const lastDay = new Date(year, month + 1, 0)
    const startPadding = firstDay.getDay() // 0 = Sunday

    const today = new Date()
    today.setHours(0, 0, 0, 0)

    // Previous month days
    const prevMonth = new Date(year, month, 0)
    for (let i = startPadding - 1; i >= 0; i--) {
      const day = prevMonth.getDate() - i
      const date = new Date(year, month - 1, day)
      days.push(this.renderDay(date, true))
    }

    // Current month days
    for (let day = 1; day <= lastDay.getDate(); day++) {
      const date = new Date(year, month, day)
      days.push(this.renderDay(date, false))
    }

    // Next month days
    const remaining = 42 - days.length // 6 rows * 7 days
    for (let day = 1; day <= remaining; day++) {
      const date = new Date(year, month + 1, day)
      days.push(this.renderDay(date, true))
    }

    return days.join("")
  }

  renderDay(date, isOtherMonth) {
    const today = new Date()
    today.setHours(0, 0, 0, 0)

    const compareDate = new Date(date)
    compareDate.setHours(0, 0, 0, 0)

    const isToday = compareDate.getTime() === today.getTime()
    const isSelected = this.pendingSelection &&
      compareDate.getTime() === new Date(this.pendingSelection).setHours(0, 0, 0, 0)

    const classes = ["due-date-picker__day"]
    if (isOtherMonth) classes.push("due-date-picker__day--other-month")
    if (isToday) classes.push("due-date-picker__day--today")
    if (isSelected) classes.push("due-date-picker__day--selected")

    const dateStr = this.formatISO(date)
    const ariaLabel = date.toLocaleDateString("en-US", { weekday: "long", year: "numeric", month: "long", day: "numeric" })

    return `
      <button type="button"
              class="${classes.join(" ")}"
              data-date="${dateStr}"
              data-action="click->due-date-picker#selectDate"
              aria-label="${ariaLabel}"
              ${isSelected ? 'aria-selected="true"' : ""}
              ${isToday ? 'aria-current="date"' : ""}>
        ${date.getDate()}
      </button>
    `
  }

  updateSaveButton() {
    const saveBtn = this.modal.querySelector("[data-save-button]")
    if (saveBtn) {
      // Enable save button if there's a pending selection different from current
      const hasPending = this.pendingSelection !== null
      const isDifferent = !this.selectedDate ||
        this.formatISO(this.pendingSelection) !== this.formatISO(this.selectedDate)
      saveBtn.disabled = !(hasPending && isDifferent)
    }
  }

  formatISO(date) {
    if (!date) return null
    const year = date.getFullYear()
    const month = String(date.getMonth() + 1).padStart(2, "0")
    const day = String(date.getDate()).padStart(2, "0")
    return `${year}-${month}-${day}`
  }
}
