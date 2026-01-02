# Feature Spec: Due Date Component

A reusable frontend component for displaying and selecting due dates on tasks.

## Overview

The due date component has two states:
1. **Display state**: Shows the due date with a calendar icon and color-coded urgency
2. **Picker state**: Modal overlay for selecting a new date

---

## Display State

### Format

The due date displays as a calendar icon followed by a short-form date label:

| Condition | Format | Example |
|-----------|--------|---------|
| Today | "Today" | Today |
| Tomorrow | "Tomorrow" | Tomorrow |
| Within current year | "Mon D" | Jan 9 |
| Different year | "Mon YYYY" | Mar 2027 |
| No due date | — | (hidden or placeholder) |

### Urgency Colors

| Level | Color | Condition | Icon |
|-------|-------|-----------|------|
| Urgent | Red | Overdue or due today | Calendar with `!` |
| Soon | Orange | Due tomorrow | Calendar |
| This week | Green | Due in 2-7 days | Calendar |
| Later | Grey | Due in 8+ days | Calendar |

### Icons

- **Standard**: Simple calendar outline icon
- **Urgent**: Calendar icon with exclamation mark overlay (for overdue/today)

### Interaction

Clicking the due date display opens the picker modal.

---

## Picker State

### Layout

Centered modal overlay with semi-transparent backdrop.

```
┌─────────────────────────────────────────────────────────┐
│  Edit due date                                     ✕    │
├─────────────────────────────────────────────────────────┤
│                                                         │
│   January 2026              February 2026        < >    │
│   Su Mo Tu We Th Fr Sa      Su Mo Tu We Th Fr Sa        │
│               1 [2] 3             1  2  3  4  5  6  7   │
│    4  5  6  7  8  9 10       8  9 10 11 12 13 14        │
│   11 12 13 14 15 16 17      15 16 17 18 19 20 21        │
│   18 19 20 21 22 23 24      22 23 24 25 26 27 28        │
│   25 26 27 28 29 30 31                                  │
│                                                         │
├─────────────────────────────────────────────────────────┤
│  [Remove due date]      [Next Week] [Tomorrow] [Today]  │
│                                        [Save due date]  │
└─────────────────────────────────────────────────────────┘
```

### Calendar Grid

- Shows **two months** side-by-side: current month and next month
- **Today** is visually highlighted (e.g., circle/ring)
- **Selected date** has filled highlight (distinct from today highlight)
- Navigation arrows (`<` `>`) shift both months forward/backward
- Days from adjacent months shown in muted style

### Quick Action Buttons

| Button | Behavior |
|--------|----------|
| Remove due date | Clears due date, saves immediately, closes picker |
| Today | Sets due date to today, saves immediately, closes picker |
| Tomorrow | Sets due date to tomorrow, saves immediately, closes picker |
| Next Week | Sets due date to 7 days from today, saves immediately, closes picker |

### Custom Date Selection

1. User clicks a date in the calendar grid
2. Date is visually selected (but not yet saved)
3. User clicks **"Save due date"** button
4. Due date is saved and picker closes

### Dismissal

- **Click outside modal**: Dismisses picker, discards unsaved selection
- **Click ✕ button**: Dismisses picker, discards unsaved selection
- **Escape key**: Dismisses picker, discards unsaved selection

---

## Technical Implementation

### Stimulus Controller

Name: `due-date-picker`

```html
<div data-controller="due-date-picker"
     data-due-date-picker-url-value="/tasks/123/due_date"
     data-due-date-picker-date-value="2026-01-15">

  <!-- Display state (trigger) -->
  <button data-action="due-date-picker#open"
          data-due-date-picker-target="display">
    <svg><!-- calendar icon --></svg>
    <span data-due-date-picker-target="label">Jan 15</span>
  </button>

  <!-- Picker modal (hidden by default) -->
  <div data-due-date-picker-target="modal" class="hidden">
    <!-- Modal content -->
  </div>
</div>
```

### Data Flow

1. Component receives current due date via `data-due-date-picker-date-value`
2. Component receives save endpoint via `data-due-date-picker-url-value`
3. On save, sends `PATCH` request with `{ due_date: "2026-01-15" }` or `{ due_date: null }`
4. Server responds with Turbo Stream to update the display

### Controller Targets

| Target | Description |
|--------|-------------|
| `display` | The clickable due date display element |
| `label` | Text span showing formatted date |
| `icon` | Calendar icon (for swapping standard/urgent) |
| `modal` | The picker modal container |
| `backdrop` | Semi-transparent overlay behind modal |
| `calendar` | Calendar grid container |
| `monthLabel` | Current displayed month/year labels |
| `saveButton` | "Save due date" button (enabled when custom date selected) |

### Controller Actions

| Action | Trigger | Description |
|--------|---------|-------------|
| `open` | Click display | Opens picker modal |
| `close` | Click ✕, backdrop, Escape | Closes picker, discards changes |
| `prevMonth` | Click `<` | Navigate calendars back one month |
| `nextMonth` | Click `>` | Navigate calendars forward one month |
| `selectDate` | Click calendar day | Select date (visual only) |
| `saveCustom` | Click "Save due date" | Save selected date, close |
| `quickSelect` | Click quick button | Save preset date, close |
| `remove` | Click "Remove due date" | Clear due date, save, close |

### Keyboard Navigation

| Key | Action |
|-----|--------|
| `Escape` | Close picker |
| `Arrow Left` | Move selection to previous day |
| `Arrow Right` | Move selection to next day |
| `Arrow Up` | Move selection to same day previous week |
| `Arrow Down` | Move selection to same day next week |
| `Enter` | Confirm current selection (triggers save) |
| `Tab` | Navigate between interactive elements |

---

## CSS Classes

### Display State

```css
.due-date { }
.due-date--urgent { }    /* Red: overdue/today */
.due-date--soon { }      /* Orange: tomorrow */
.due-date--week { }      /* Green: 2-7 days */
.due-date--later { }     /* Grey: 8+ days */
```

### Picker Modal

```css
.due-date-picker { }
.due-date-picker__backdrop { }
.due-date-picker__modal { }
.due-date-picker__header { }
.due-date-picker__calendars { }
.due-date-picker__month { }
.due-date-picker__nav { }
.due-date-picker__grid { }
.due-date-picker__day { }
.due-date-picker__day--today { }
.due-date-picker__day--selected { }
.due-date-picker__day--other-month { }
.due-date-picker__actions { }
```

---

## Server Integration

### Endpoint

```
PATCH /tasks/:id/due_date
```

### Request Body

```json
{ "due_date": "2026-01-15" }
```

or to remove:

```json
{ "due_date": null }
```

### Response

Turbo Stream updating the due date display:

```html
<turbo-stream action="replace" target="task_123_due_date">
  <template>
    <div id="task_123_due_date" ...>
      <!-- Updated due date display -->
    </div>
  </template>
</turbo-stream>
```

---

## Accessibility

- Modal traps focus when open
- Calendar days are focusable with `tabindex`
- `aria-label` on days includes full date (e.g., "Friday, January 9, 2026")
- `aria-selected` indicates currently selected date
- `aria-current="date"` on today's date
- Modal has `role="dialog"` and `aria-modal="true"`
- Close button has `aria-label="Close"`

---

## Edge Cases

| Scenario | Behavior |
|----------|----------|
| No due date set | Display shows placeholder or is hidden |
| Due date in distant past | Shows red with alert icon, format "Mon YYYY" if different year |
| Due date far in future | Shows grey, format "Mon YYYY" if different year |
| Save fails (network error) | Show error toast, keep picker open |
| Rapid clicking | Debounce save requests |

---

## Design References

Component follows the project's design system:
- See `doc/ui.md` for color palette and button styles
- Pill-shaped buttons for actions
- Blue-grey primary color from project palette
