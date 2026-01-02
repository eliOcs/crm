module DueDateHelper
  # Format due date for display
  # Returns: "Today", "Tomorrow", "Jan 9", "Mar 2027"
  def format_due_date(date)
    return nil unless date

    today = Date.current
    tomorrow = today + 1.day

    case date
    when today
      t("due_date.today")
    when tomorrow
      t("due_date.tomorrow")
    else
      if date.year == today.year
        l(date, format: :short_no_year)
      else
        l(date, format: :short_with_year)
      end
    end
  end

  # Determine urgency level based on days until due
  # Returns: :urgent, :soon, :week, :later, or nil
  def due_date_urgency(date)
    return nil unless date

    days_until = (date - Date.current).to_i

    if days_until <= 0
      :urgent    # Overdue or due today
    elsif days_until == 1
      :soon      # Tomorrow
    elsif days_until <= 7
      :week      # 2-7 days away
    else
      :later     # 8+ days away
    end
  end

  # CSS class for the due date display based on urgency
  def due_date_class(date)
    urgency = due_date_urgency(date)
    return "due-date due-date--empty" unless urgency

    "due-date due-date--#{urgency}"
  end

  # Calendar icon SVG - standard version
  def due_date_icon_standard
    <<~SVG.html_safe
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor">
        <path fill-rule="evenodd" d="M5.75 2a.75.75 0 0 1 .75.75V4h7V2.75a.75.75 0 0 1 1.5 0V4h.25A2.75 2.75 0 0 1 18 6.75v8.5A2.75 2.75 0 0 1 15.25 18H4.75A2.75 2.75 0 0 1 2 15.25v-8.5A2.75 2.75 0 0 1 4.75 4H5V2.75A.75.75 0 0 1 5.75 2Zm-1 5.5c-.69 0-1.25.56-1.25 1.25v6.5c0 .69.56 1.25 1.25 1.25h10.5c.69 0 1.25-.56 1.25-1.25v-6.5c0-.69-.56-1.25-1.25-1.25H4.75Z" clip-rule="evenodd" />
      </svg>
    SVG
  end

  # Calendar icon SVG - urgent version with exclamation mark
  def due_date_icon_urgent
    <<~SVG.html_safe
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor">
        <path fill-rule="evenodd" d="M5.75 2a.75.75 0 0 1 .75.75V4h7V2.75a.75.75 0 0 1 1.5 0V4h.25A2.75 2.75 0 0 1 18 6.75v8.5A2.75 2.75 0 0 1 15.25 18H4.75A2.75 2.75 0 0 1 2 15.25v-8.5A2.75 2.75 0 0 1 4.75 4H5V2.75A.75.75 0 0 1 5.75 2Zm-1 5.5c-.69 0-1.25.56-1.25 1.25v6.5c0 .69.56 1.25 1.25 1.25h10.5c.69 0 1.25-.56 1.25-1.25v-6.5c0-.69-.56-1.25-1.25-1.25H4.75Z" clip-rule="evenodd" />
        <path d="M10 10a.75.75 0 0 1 .75.75v2a.75.75 0 0 1-1.5 0v-2A.75.75 0 0 1 10 10Zm0 5a.75.75 0 1 0 0-1.5.75.75 0 0 0 0 1.5Z" />
      </svg>
    SVG
  end

  # Get the appropriate icon based on urgency
  def due_date_icon(urgency)
    if urgency == :urgent
      due_date_icon_urgent
    else
      due_date_icon_standard
    end
  end
end
