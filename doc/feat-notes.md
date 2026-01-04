# Notes Feature

## Overview

Add rich-text notes to contacts and companies, allowing users to record free-form information with basic text formatting. Notes will be editable directly in the detail views using Lexxy, a modern rich text editor built on Lexical.

## User Stories

- As a user, I want to add notes to a contact so I can remember context about our relationship
- As a user, I want to add notes to a company so I can track important information about the organization
- As a user, I want basic text formatting (bold, italic, links) so my notes are easier to read
- As a user, I want to edit notes inline without leaving the detail page

## Technology

### Lexxy Editor

[Lexxy](https://github.com/basecamp/lexxy) is a modern rich text editor for Rails built on Meta's Lexical framework.

**Key features:**
- Semantic HTML output (`<p>`, `<strong>`, `<em>`, etc.)
- Markdown shortcuts (e.g., `**bold**`, `*italic*`)
- Link creation by pasting URLs over selected text
- Action Text integration (generates compatible HTML)
- Minimal toolbar

**Status:** Early beta (v0.1.23). Suitable for internal CRM use.

### Dependencies

```ruby
# Gemfile
gem "lexxy", "~> 0.1.23.beta"
```

```ruby
# config/importmap.rb
pin "lexxy", to: "lexxy.js"
pin "@rails/activestorage", to: "activestorage.esm.js"
```

## Database Schema

Uses Rails Action Text for rich content storage. No custom migrations needed for the text content itself.

```ruby
# Install Action Text (if not already installed)
bin/rails action_text:install
```

This creates:
- `action_text_rich_texts` table (polymorphic, stores HTML content)
- `active_storage_blobs` + `active_storage_attachments` (for embedded images)

## Implementation Plan

### Phase 1: Setup

#### 1.1 Install Dependencies

```bash
# Add gem
bundle add lexxy --version "~> 0.1.23.beta"

# Install Action Text (if needed)
bin/rails action_text:install
bin/rails db:migrate
```

#### 1.2 Configure Importmap

```ruby
# config/importmap.rb
pin "lexxy", to: "lexxy.js"
pin "@rails/activestorage", to: "activestorage.esm.js"
```

#### 1.3 Import JavaScript

```javascript
// app/javascript/application.js
import "lexxy"
```

#### 1.4 Include Stylesheet

```erb
<%# app/views/layouts/application.html.erb %>
<%= stylesheet_link_tag "lexxy" %>
```

### Phase 2: Models

#### 2.1 Add Notes to Contact

```ruby
# app/models/contact.rb
class Contact < ApplicationRecord
  has_rich_text :notes
  # ... existing code
end
```

#### 2.2 Add Notes to Company

```ruby
# app/models/company.rb
class Company < ApplicationRecord
  has_rich_text :notes
  # ... existing code
end
```

### Phase 3: Views

#### 3.1 Notes Section Partial

Create a reusable notes section for both detail views:

```erb
<%# app/views/shared/_notes_section.html.erb %>
<section class="section notes-section">
  <div class="section__header">
    <h2 class="section__title"><%= t("notes.title") %></h2>
  </div>

  <div id="<%= dom_id(record, :notes) %>">
    <%= turbo_frame_tag dom_id(record, :notes_editor) do %>
      <% if record.notes.present? %>
        <div class="notes-content lexxy-content">
          <%= record.notes %>
        </div>
        <%= button_to t("notes.edit"),
            polymorphic_path(record, action: :edit_notes),
            method: :get,
            class: "btn btn--secondary btn--sm",
            data: { turbo_frame: dom_id(record, :notes_editor) } %>
      <% else %>
        <%= button_to t("notes.add"),
            polymorphic_path(record, action: :edit_notes),
            method: :get,
            class: "btn btn--secondary btn--sm",
            data: { turbo_frame: dom_id(record, :notes_editor) } %>
      <% end %>
    <% end %>
  </div>
</section>
```

#### 3.2 Notes Editor Partial

```erb
<%# app/views/shared/_notes_editor.html.erb %>
<%= turbo_frame_tag dom_id(record, :notes_editor) do %>
  <%= form_with model: record,
                url: polymorphic_path(record),
                method: :patch,
                class: "notes-form" do |form| %>

    <%= form.rich_text_area :notes,
        placeholder: t("notes.placeholder"),
        toolbar: "basic" %>

    <div class="notes-form__actions">
      <%= form.submit t("notes.save"), class: "btn btn--primary btn--sm" %>
      <%= link_to t("notes.cancel"),
          polymorphic_path(record),
          class: "btn btn--secondary btn--sm",
          data: { turbo_frame: dom_id(record, :notes_editor) } %>
    </div>
  <% end %>
<% end %>
```

#### 3.3 Update Contact Detail View

```erb
<%# app/views/contacts/show.html.erb %>
<%# ... existing content ... %>

<%= render "shared/notes_section", record: @contact %>

<%= render "shared/audit_log_section", record: @contact %>
```

#### 3.4 Update Company Detail View

```erb
<%# app/views/companies/show.html.erb %>
<%# ... existing content ... %>

<%= render "shared/notes_section", record: @company %>

<%= render "shared/audit_log_section", record: @company %>
```

### Phase 4: Controllers

#### 4.1 Update ContactsController

```ruby
# app/controllers/contacts_controller.rb
class ContactsController < ApplicationController
  include InlineEditable
  inline_editable :name, :job_role, :department, :phone_numbers

  def show
    @contact = Current.user.contacts.find(params[:id])
  end

  def edit_notes
    @contact = Current.user.contacts.find(params[:id])
    render partial: "shared/notes_editor", locals: { record: @contact }
  end

  def update
    @contact = Current.user.contacts.find(params[:id])

    if params[:contact]&.key?(:notes)
      update_notes(@contact)
    else
      inline_update(@contact)
    end
  end

  private

  def update_notes(record)
    if record.update(notes: params[:contact][:notes])
      redirect_to record
    else
      render partial: "shared/notes_editor", locals: { record: record }, status: :unprocessable_entity
    end
  end
end
```

#### 4.2 Update CompaniesController

```ruby
# app/controllers/companies_controller.rb
class CompaniesController < ApplicationController
  include InlineEditable
  inline_editable :legal_name, :commercial_name, :domain, :location, :website, :vat_id

  def show
    @company = Current.user.companies.find(params[:id])
    @contacts = @company.contacts.order(:name)
  end

  def edit_notes
    @company = Current.user.companies.find(params[:id])
    render partial: "shared/notes_editor", locals: { record: @company }
  end

  def update
    @company = Current.user.companies.find(params[:id])

    if params[:company]&.key?(:notes)
      update_notes(@company)
    else
      inline_update(@company)
    end
  end

  private

  def update_notes(record)
    if record.update(notes: params[:company][:notes])
      redirect_to record
    else
      render partial: "shared/notes_editor", locals: { record: record }, status: :unprocessable_entity
    end
  end
end
```

### Phase 5: Routes

```ruby
# config/routes.rb
resources :contacts do
  member do
    get :edit_notes
  end
end

resources :companies do
  member do
    get :edit_notes
  end
end
```

### Phase 6: Styling

#### 6.1 Notes Component Styles

```css
/* app/assets/stylesheets/notes.css */
@layer components {
  .notes-section {
    margin-block-start: var(--space-lg);
  }

  .notes-content {
    padding: var(--space-md);
    background: var(--color-surface);
    border-radius: var(--radius-md);
    min-block-size: 4rem;
  }

  .notes-content:empty::before {
    content: attr(data-placeholder);
    color: var(--color-text-subtle);
  }

  .notes-form {
    display: flex;
    flex-direction: column;
    gap: var(--space-sm);
  }

  .notes-form__actions {
    display: flex;
    gap: var(--space-xs);
    justify-content: flex-end;
  }

  /* Lexxy editor overrides */
  lexxy-editor {
    --lexxy-border-color: var(--color-border);
    --lexxy-focus-color: var(--color-primary);
    --lexxy-background: var(--color-surface);
    min-block-size: 8rem;
  }
}
```

### Phase 7: I18n

```yaml
# config/locales/en.yml
en:
  notes:
    title: "Notes"
    add: "Add notes"
    edit: "Edit notes"
    save: "Save"
    cancel: "Cancel"
    placeholder: "Add notes about this record..."
```

```yaml
# config/locales/es.yml
es:
  notes:
    title: "Notas"
    add: "Agregar notas"
    edit: "Editar notas"
    save: "Guardar"
    cancel: "Cancelar"
    placeholder: "Agregar notas sobre este registro..."
```

## UI/UX Design

### Notes Section Layout

```
┌─────────────────────────────────────────────┐
│ Notes                                       │
├─────────────────────────────────────────────┤
│                                             │
│ Meeting on 2024-01-15: Discussed Q1         │
│ targets. Key contact for **Barcelona**      │
│ office.                                     │
│                                             │
│ Follow up about proposal next week.         │
│                                             │
├─────────────────────────────────────────────┤
│                              [Edit notes]   │
└─────────────────────────────────────────────┘
```

### Editor Mode

```
┌─────────────────────────────────────────────┐
│ Notes                                       │
├─────────────────────────────────────────────┤
│ ┌─────────────────────────────────────────┐ │
│ │ B I U Link                              │ │
│ ├─────────────────────────────────────────┤ │
│ │ Meeting on 2024-01-15: Discussed Q1     │ │
│ │ targets. Key contact for **Barcelona**  │ │
│ │ office.                                 │ │
│ │                                         │ │
│ │ Follow up about proposal next week.     │ │
│ │                                         │ │
│ └─────────────────────────────────────────┘ │
│                       [Cancel]  [Save]      │
└─────────────────────────────────────────────┘
```

## Formatting Options

Lexxy provides these formatting options out of the box:

| Format | Toolbar | Markdown Shortcut |
|--------|---------|-------------------|
| Bold | B button | `**text**` |
| Italic | I button | `*text*` |
| Underline | U button | - |
| Link | Link button | Paste URL over selection |
| Bullet list | - | `- item` at line start |
| Numbered list | - | `1. item` at line start |

For this feature, we'll use the basic toolbar (bold, italic, link) to keep the interface simple.

## Attachments

**Not included in initial implementation.** Lexxy supports attachments but adds complexity:
- Requires Active Storage setup for embedded files
- Increases storage requirements
- More complex HTML sanitization needed

Can be added later if users request embedded images/files in notes.

## Security Considerations

### HTML Sanitization

Action Text automatically sanitizes HTML content using Rails' built-in sanitizer. This prevents XSS attacks from malicious HTML.

### Authorization

All notes are scoped to `Current.user`:
- Users can only view/edit notes on their own contacts and companies
- Controller actions verify ownership before allowing access

## Testing

### Model Tests

```ruby
# test/models/contact_test.rb
class ContactTest < ActiveSupport::TestCase
  test "contact can have rich text notes" do
    contact = contacts(:one)
    contact.notes = "<p>Test <strong>note</strong></p>"
    contact.save!

    assert_equal "<p>Test <strong>note</strong></p>", contact.notes.body.to_s
  end
end
```

### System Tests

```ruby
# test/system/notes_test.rb
class NotesTest < ApplicationSystemTestCase
  setup do
    sign_in users(:one)
    @contact = contacts(:one)
  end

  test "adding notes to a contact" do
    visit contact_path(@contact)

    click_button "Add notes"

    within "lexxy-editor" do
      fill_in with: "Important meeting scheduled"
    end

    click_button "Save"

    assert_text "Important meeting scheduled"
  end

  test "editing existing notes" do
    @contact.update!(notes: "Original note")
    visit contact_path(@contact)

    click_button "Edit notes"

    within "lexxy-editor" do
      fill_in with: "Updated note"
    end

    click_button "Save"

    assert_text "Updated note"
    assert_no_text "Original note"
  end
end
```

## Migration Path

1. Add `lexxy` gem and configure importmap
2. Run `bin/rails action_text:install` if not already done
3. Add `has_rich_text :notes` to models
4. Add controller actions and routes
5. Update views with notes section
6. Add styles and translations
7. Test thoroughly

## Future Enhancements

- **Search notes:** Include notes content in universal search (Phase 2)
- **Attachments:** Allow embedded images/files in notes
- **Mentions:** `@contact` mentions to link related records
- **History:** Track note revisions with timestamps
- **Templates:** Pre-defined note templates for common scenarios

## Implementation Learnings

### Stylesheet Loading Order (Critical)

**Problem:** When Lexxy's CSS loads AFTER the app CSS, our custom styles are overridden, requiring `!important` everywhere.

**Solution:** Load Lexxy CSS BEFORE app CSS in the layout:

```erb
<%# app/views/layouts/application.html.erb %>
<%# Lexxy CSS loads first so our app styles can override %>
<%= stylesheet_link_tag "lexxy" %>
<%= stylesheet_link_tag :app, "data-turbo-track": "reload" %>
```

This follows the same pattern used by Fizzy and allows natural CSS cascade without `!important` hacks.

### Custom Toolbar with External Placement

When using a custom toolbar defined outside the `<lexxy-editor>` element (via the `toolbar` attribute), several considerations apply:

1. **Toolbar connection:** Use `toolbar` attribute on `rich_text_area` pointing to the toolbar's ID
2. **Form nesting:** The toolbar contains a `<form method="dialog">` for the link dropdown - place toolbar OUTSIDE your main form to avoid invalid nested forms
3. **Overflow menu:** Lexxy expects an overflow menu element even if hidden:

```erb
<details class="lexxy-editor__toolbar-overflow" hidden>
  <summary class="lexxy-editor__toolbar-button" aria-label="Show more toolbar buttons">•••</summary>
  <div class="lexxy-editor__toolbar-overflow-menu" aria-label="More toolbar buttons"></div>
</details>
```

### CSS Variable Overrides

Override Lexxy's accent colors at the toolbar level to change selected/active states:

```css
lexxy-toolbar {
  /* Override Lexxy's accent colors with neutral grays */
  --lexxy-color-accent-lightest: oklch(var(--lch-canvas-alt));
  --lexxy-color-accent-light: var(--color-border);
  --lexxy-toolbar-gap: 0.5em;
  --lexxy-toolbar-icon-size: 0.85em;
}
```

Key variables:
- `--lexxy-color-accent-lightest` → Selected button background
- `--lexxy-color-accent-light` → Selected + hover background
- `--lexxy-toolbar-gap` → Spacing between toolbar buttons
- `--lexxy-toolbar-icon-size` → Icon dimensions

### Toolbar Button Styling

For circular buttons with custom sizing:

```css
.lexxy-editor__toolbar-button {
  appearance: none;
  aspect-ratio: 1;
  background-color: transparent;
  block-size: 2em;
  border: none;
  border-radius: 50%;
  color: var(--color-ink-subtle);
  cursor: pointer;
  display: grid;
  font-size: inherit;
  place-items: center;

  &:is(:focus, :hover) {
    background-color: var(--color-canvas-alt);
    color: var(--color-ink);
  }
}
```

### Link Dropdown Styling

Style the link dropdown to match app design:

```css
.lexxy-editor__toolbar-dropdown-content {
  background-color: oklch(var(--lch-white));
  border: 1px solid var(--color-border);
  border-radius: var(--card-radius);
  box-shadow: 0 4px 12px oklch(var(--lch-ink) / 0.1);
  padding: var(--block-space);
}

lexxy-link-dropdown {
  input[type="url"] {
    /* Match app input styles */
  }

  button {
    /* Secondary button style */
  }

  button[value="link"] {
    /* Primary button style */
  }
}
```

### Files Created/Modified

| File | Purpose |
|------|---------|
| `app/views/shared/_simple_toolbar.html.erb` | Custom minimal toolbar (B, I, Link, Lists, Undo/Redo) |
| `app/views/shared/_notes_editor.html.erb` | Editor form with external toolbar |
| `app/views/shared/_notes_section.html.erb` | Display/edit toggle section |
| `app/assets/stylesheets/notes.css` | All Lexxy customizations |
| `app/views/layouts/application.html.erb` | Stylesheet load order fix |

### Hidden Features

Hide unwanted Lexxy features with CSS:

```css
/* Hide code language picker - not needed for notes */
lexxy-code-language-picker,
.lexxy-code-language-picker {
  display: none;
}
```

## References

- [Lexxy GitHub](https://github.com/basecamp/lexxy)
- [Action Text Guide](https://guides.rubyonrails.org/action_text_overview.html)
- [Lexical Editor](https://lexical.dev/)
