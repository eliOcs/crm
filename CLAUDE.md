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
ANTHROPIC_API_KEY=sk-ant-...  # Required for LLM features (enrichment, dedup)
```

## Key Commands

```bash
# Development
bin/rails server          # Start dev server
bin/rails test            # Run tests
bin/rubocop               # Lint code
bin/setup                 # Setup project (installs deps, configures git hooks)

# Import tasks
bin/rails import:contacts         # Import contacts from EML files (prompts for user email)
bin/rails import:enrich_contacts  # Enrich contacts/companies with LLM (extracts job roles, phones, companies, logos)
bin/rails import:dedup_companies  # LLM-powered company deduplication (finds duplicates by name/logo)
bin/extract-pst <file>            # Extract EML files from PST backup

# Database
bin/rails db:migrate      # Run migrations
bin/rails db:reset        # Reset database
```

## Project Structure

```
app/
├── controllers/
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
│   ├── eml_contact_extractor.rb  # Extract contacts from EML headers
│   ├── llm_email_extractor.rb    # LLM-powered extraction (contacts, companies, logos)
│   ├── company_web_enricher.rb   # Web search enrichment for companies (Claude + web search)
│   └── llm_company_deduplicator.rb # LLM-powered company deduplication
└── views/
    ├── shared/_navbar.html.erb   # Navigation (shown when authenticated)
    └── ...

db/seeds/emails/          # EML files extracted from PST (gitignored)
lib/tasks/
├── import_contacts.rake  # Contact import task
├── enrich_contacts.rake  # LLM enrichment task (contacts, companies, web search)
└── dedup_companies.rake  # LLM-powered company deduplication
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

# Extracting contacts (from headers only)
contacts = EmlContactExtractor.new(path).extract
# => [{ email:, name: }, ...]

# LLM-powered extraction (contacts + companies + logos) - uses Claude 3.5 Haiku
result = LlmEmailExtractor.new(path).extract
# => { contacts: [{email:, name:, job_role:, phone_numbers:, company_name:}, ...],
#      companies: [{legal_name:, commercial_name:, website:, logo_content_id:}, ...],
#      image_data: {content_id => {content_type:, base64_data:, raw_data:}, ...} }

# Web search enrichment for companies - uses Claude Sonnet + web search
enriched = CompanyWebEnricher.new("ACME", hint_domain: "acme.com").enrich
# => { legal_name:, commercial_name:, website:, description:, industry:, location: }
```

### LLM Models Used
- **Claude 3.5 Haiku** (`claude-3-5-haiku-latest`): Email extraction (fast, cost-effective)
- **Claude Sonnet 4.5** (`claude-sonnet-4-5-20250929`): Web enrichment with web search tool, company deduplication

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

companies
├── user_id (FK)
├── legal_name (required)
├── commercial_name (brand/trade name)
├── domain (normalized from website, unique per user)
├── website
├── description
├── industry
├── location
├── web_enriched_at (timestamp when web search enrichment was done)
├── logo (Active Storage attachment)
└── timestamps

contacts
├── user_id (FK)
├── email (unique per user, normalized lowercase)
├── name
├── job_role
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
