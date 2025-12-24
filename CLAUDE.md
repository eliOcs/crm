# CLAUDE.md

## Project Overview

CRM application for managing contacts, companies, and emails. Built to help parse and organize email data from Outlook PST backups, with plans to integrate with Microsoft Exchange in the future.

## Tech Stack

- **Ruby on Rails 8.1.1** with SQLite
- **Ruby 3.4.7**
- **Hotwire** (Turbo + Stimulus) for frontend
- **Propshaft** for asset pipeline
- **Importmaps** for JavaScript (no Node.js required)
- **Anthropic Claude API** for LLM-powered features (via `anthropic` gem)

## Environment Variables

```bash
ANTHROPIC_API_KEY=sk-ant-...  # Required for LLM features (enrichment)
EMAILS_DIR=/path/to/emails    # Optional: Override default db/seeds/emails location
```

## Key Commands

```bash
# Development
bin/rails server          # Start dev server
bin/rails test            # Run tests
bin/rubocop               # Lint code
bin/setup                 # Setup project (installs deps, configures git hooks)

# Import tasks
bin/rails import:process_emails   # Process emails: extract contacts, companies, and tasks via LLM
bin/extract-pst <file>            # Extract EML files from PST backup
bin/reset-and-import              # Reset DB and import (use LIMIT=N for fewer emails)

# Database
bin/rails db:migrate      # Run migrations
bin/rails db:reset        # Reset database

# Production
bin/sync-to-production    # Sync database, logos, and referenced EML files to production
bin/kamal deploy          # Deploy to production
bin/kamal console         # Rails console on production
bin/kamal logs            # Tail production logs
```

## Project Structure

```
app/
├── controllers/
│   ├── concerns/
│   │   └── inline_editable.rb    # Shared inline editing logic
│   ├── companies_controller.rb   # Company list and detail
│   ├── contacts_controller.rb    # Contact list
│   ├── dashboard_controller.rb   # Home page (logged in)
│   ├── emails_controller.rb      # Email list and view
│   ├── registrations_controller.rb
│   └── sessions_controller.rb
├── models/
│   ├── user.rb                   # has_many :contacts, :companies, :sessions
│   ├── company.rb                # belongs_to :user, has_and_belongs_to_many :contacts
│   ├── contact.rb                # belongs_to :user, has_and_belongs_to_many :companies
│   ├── session.rb                # Auth sessions
│   └── current.rb                # CurrentAttributes for request context
├── services/
│   ├── eml_reader.rb             # Parse EML files, extract attachments
│   ├── llm_email_extractor.rb    # LLM-powered extraction (contacts, companies, logos)
│   └── contact_enrichment_service.rb # Orchestrates contact/company enrichment from emails
└── views/
    ├── shared/_navbar.html.erb   # Navigation (shown when authenticated)
    └── ...

db/seeds/emails/          # EML files extracted from PST (gitignored)
lib/tasks/
└── enrich_contacts.rake  # LLM enrichment task (contacts, companies from emails)
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

# LLM-powered extraction (contacts + companies + logos) - uses Claude Haiku 4.5
result = LlmEmailExtractor.new(path).extract
# => { contacts: [{email:, name:, job_role:, department:, phone_numbers:}, ...],
#      companies: [{legal_name:, commercial_name:, domain:, website:, location:, vat_id:, logo_content_id:}, ...],
#      image_data: {content_id => {content_type:, base64_data:, raw_data:}, ...} }
```

### LLM Models Used
- **Claude Haiku 4.5** (`claude-haiku-4-5-20251001`): Email extraction (fast, cost-effective)

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

### InlineEditable Concern
Controllers that support inline field editing include `InlineEditable`:
```ruby
class ContactsController < ApplicationController
  include InlineEditable
  inline_editable :name, :job_role, :department, :phone_numbers

  def update
    @contact = Current.user.contacts.find(params[:id])
    inline_update(@contact)
  end
end
```

The concern:
- Validates field is in allowed list
- Creates audit log entry with old/new values
- Renders shared Turbo Stream template (`shared/inline_update.turbo_stream.erb`)
- Override `transform_value(field, value)` for custom parsing (e.g., comma-separated phone numbers)

### Audit Log Paths
Audit logs store source email paths **relative** to `EMAILS_DIR` for portability:
- Stored: `Company/123/email.eml`
- Full path reconstructed: `EmlReader::EMAILS_DIR.join(relative_path)`

## Git Workflow

Pre-commit hook runs automatically:
1. Rubocop (linting)
2. Full test suite

Hook location: `.githooks/pre-commit` (tracked in git)
Configured via: `git config core.hooksPath .githooks`

## Testing

### VCR for API Tests
Tests that call external APIs (Anthropic, web search) use VCR to record and replay HTTP interactions:

```ruby
# test/services/contact_enrichment_service_test.rb
VCR.use_cassette("enrichment_company_hierarchy") do
  service = ContactEnrichmentService.new(@user, logger: @logger)
  service.process_email(eml_path)
end
```

- Cassettes stored in `test/cassettes/` (YAML files with recorded HTTP responses)
- First run records real API calls, subsequent runs replay from cassettes
- API keys filtered automatically via `config.filter_sensitive_data`
- To re-record: delete the cassette file and run tests with `ANTHROPIC_API_KEY` set

Configuration: `test/support/vcr.rb`

## Important Files

- `doc/ui.md` - Design style guide (Swiss Style, blue-grey palette, pill buttons)
- `doc/css-best-practices.md` - CSS architecture patterns
- `doc/best-practices.md` - Rails 7+ conventions and patterns (READ THIS)
- `.gitignore` - Ignores `db/seeds/emails/` and `*.pst` files
- `config/routes.rb` - All routes defined here
- `config/deploy.yml` - Kamal deployment configuration
- `bin/sync-to-production` - Sync local data to production

## CSS Architecture

Pure modern CSS (no preprocessors). Uses `@layer` for cascade control and OKLCH colors.

### File Structure
```
app/assets/stylesheets/
├── _global.css      # Layer declarations + design tokens (colors, spacing, typography)
├── reset.css        # Browser normalization
├── base.css         # Element defaults (body, headings, links)
├── utilities.css    # Helper classes (txt-*, pad-*, flex-*)
├── buttons.css      # .btn component (pill-shaped)
├── inputs.css       # Form inputs and field groups
├── tables.css       # Data tables
├── navbar.css       # Navigation bar
├── layout.css       # Container, page headers, auth layout
├── cards.css        # Info cards, email cards
├── pagination.css   # Pagination links
└── flash.css        # Alert/notice messages
```

### Key Patterns
- **BEM naming**: `.component`, `.component__element`, `.component--modifier`
- **Utility prefixes**: `txt-*`, `pad-*`, `flex-*`, `fill-*`
- **OKLCH colors**: `--lch-primary`, `--color-primary` for perceptually uniform palette
- **Logical properties**: `inline-size`, `block-size`, `margin-inline-start` (RTL-ready)
- **CSS variables**: Override component internals via `--btn-bg`, `--btn-color`, etc.

### Design Tokens
Primary color is blue-grey derived from logo (`oklch(50% 0.06 230)`). See `_global.css` for full palette.

## Database Schema

```
users
├── email_address (unique, normalized lowercase)
├── password_digest
└── timestamps

companies
├── user_id (FK)
├── legal_name (required)
├── commercial_name (brand/trade name)
├── domain (extracted from contact emails, unique per user)
├── website
├── location
├── vat_id (tax ID extracted from legal notices)
├── logo (Active Storage attachment)
└── timestamps

contacts
├── user_id (FK)
├── email (unique per user, normalized lowercase)
├── name
├── job_role
├── department
├── phone_numbers (JSON array)
└── timestamps

companies_contacts (join table, many-to-many)
├── company_id (FK)
└── contact_id (FK)

sessions
├── user_id (FK)
├── ip_address
├── user_agent
└── timestamps
```

### Company Name Fields
- `legal_name`: Full official/legal registered name (e.g., "Industrial Técnica Pecuaria, S.A.")
- `commercial_name`: Brand or trade name commonly used (e.g., "ITPSA")
- `display_name` method: Returns commercial_name if present, otherwise legal_name

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
| `/companies` | Company list |
| `/companies/:id` | Company detail with linked contacts |
| `/emails` | Email list (paginated) |
| `/emails/:id` | View email |
| `/emails/:id/attachment/:cid` | Serve inline attachment |

## Production Deployment

Uses **Kamal** for Docker-based deployment to AWS EC2 (ARM64 Graviton).

### Key Commands
```bash
bin/kamal deploy              # Full deploy
bin/kamal console             # Rails console on production
bin/kamal logs                # Tail production logs
bin/kamal shell               # SSH into container
```

### Configuration (`config/deploy.yml`)
- **Host**: `52.30.167.17` (crm.eliocapella.com)
- **Registry**: AWS ECR (eu-west-1)
- **SSL**: Auto via Let's Encrypt
- **Architecture**: ARM64 (Graviton)

### Volume Mounts
```yaml
volumes:
  - "crm_storage:/rails/storage"    # SQLite + Active Storage
  - "/root/crm-emails:/emails:ro"   # EML files (read-only)
```

### Production Sync
Sync local data to production (database, logos, and referenced EML files only):
```bash
bin/sync-to-production            # Full sync
bin/sync-to-production --dry-run  # Preview changes
```

The script:
1. Copies `storage/development.sqlite3` → production
2. Syncs Active Storage blobs (company logos)
3. Queries audit_logs for referenced EML files and syncs only those (not all 5GB)

After syncing, redeploy to pick up changes:
```bash
bin/kamal deploy
```
