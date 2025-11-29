# CLAUDE.md

## Project Overview

CRM application for managing contacts and emails. Built to help parse and organize email data from Outlook PST backups, with plans to integrate with Microsoft Exchange in the future.

## Tech Stack

- **Ruby on Rails 8.1.1** with SQLite
- **Ruby 3.4.7**
- **Hotwire** (Turbo + Stimulus) for frontend
- **Propshaft** for asset pipeline
- **Importmaps** for JavaScript (no Node.js required)

## Key Commands

```bash
# Development
bin/rails server          # Start dev server
bin/rails test            # Run tests
bin/rubocop               # Lint code
bin/setup                 # Setup project (installs deps, configures git hooks)

# Import tasks
bin/rails import:contacts # Import contacts from EML files (prompts for user email)
bin/extract-pst <file>    # Extract EML files from PST backup

# Database
bin/rails db:migrate      # Run migrations
bin/rails db:reset        # Reset database
```

## Project Structure

```
app/
├── controllers/
│   ├── contacts_controller.rb    # Contact list
│   ├── dashboard_controller.rb   # Home page (logged in)
│   ├── emails_controller.rb      # Email list and view
│   ├── registrations_controller.rb
│   └── sessions_controller.rb
├── models/
│   ├── user.rb                   # has_many :contacts, :sessions
│   ├── contact.rb                # belongs_to :user
│   ├── session.rb                # Auth sessions
│   └── current.rb                # CurrentAttributes for request context
├── services/
│   ├── eml_reader.rb             # Parse EML files, extract attachments
│   └── eml_contact_extractor.rb  # Extract contacts from EML headers
└── views/
    ├── shared/_navbar.html.erb   # Navigation (shown when authenticated)
    └── ...

db/seeds/emails/          # EML files extracted from PST (gitignored)
lib/tasks/
└── import_contacts.rake  # Contact import task
```

## Authentication

Uses Rails 8 built-in authentication generator:
- Session-based auth with `has_secure_password`
- `Current.user` available in controllers/views when logged in
- `authenticated?` helper for views
- `allow_unauthenticated_access` in controllers to skip auth

## Key Patterns

### Services
Business logic extracted into service objects in `app/services/`:
```ruby
# Reading an email
email = EmlReader.new(path).read
# => { from:, to:, subject:, date:, body:, html_body:, attachments: }

# Extracting contacts
contacts = EmlContactExtractor.new(path).extract
# => [{ email:, name: }, ...]
```

### File-based Email Storage
Emails are read directly from EML files on disk (not stored in database):
- Files located in `db/seeds/emails/`
- Base64-encoded paths used in URLs for safety
- Pagination handled by slicing file list

### CID Attachments
Inline images in emails use Content-ID references:
- Extracted via `EmlReader#attachment(content_id)`
- Served through `emails#attachment` action
- HTML `cid:xxx` references replaced with attachment URLs

## Git Workflow

Pre-commit hook runs automatically:
1. Rubocop (linting)
2. Full test suite

Hook location: `.githooks/pre-commit` (tracked in git)
Configured via: `git config core.hooksPath .githooks`

## Important Files

- `doc/best-practices.md` - Rails 7+ conventions and patterns (READ THIS)
- `.gitignore` - Ignores `db/seeds/emails/` and `*.pst` files
- `config/routes.rb` - All routes defined here

## Database Schema

```
users
├── email_address (unique, normalized lowercase)
├── password_digest
└── timestamps

contacts
├── user_id (FK)
├── email (unique per user, normalized lowercase)
├── name
└── timestamps

sessions
├── user_id (FK)
├── ip_address
├── user_agent
└── timestamps
```

## PST File Extraction

To extract emails from Outlook PST files:
```bash
# Install libpst (Arch Linux)
sudo pacman -S libpst

# Extract with single thread (avoids segfaults)
bin/extract-pst backup.pst db/seeds/emails
```

## Routes

| Path | Description |
|------|-------------|
| `/` | Dashboard (requires auth) |
| `/session/new` | Login |
| `/registration/new` | Signup |
| `/contacts` | Contact list |
| `/emails` | Email list (paginated) |
| `/emails/:id` | View email |
| `/emails/:id/attachment/:cid` | Serve inline attachment |
