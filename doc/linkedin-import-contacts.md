# LinkedIn Contact Import via DMA Portability API

## Overview

LinkedIn provides a **Member Data Portability API** for EU/EEA/Switzerland members, mandated by the Digital Markets Act (DMA) and GDPR. This API allows programmatic access to your own LinkedIn data, including connections with contact details and photos.

## Eligibility

- **Required**: LinkedIn profile location set to EU/EEA or Switzerland
- Members outside these regions receive error messages when trying to use the API

## Available Data Domains

Key domains for CRM contact enrichment:

| Domain | Data Included |
|--------|---------------|
| `CONNECTIONS` | Name, position, company, connection date of 1st-degree connections |
| `EMAIL_ADDRESSES` | Current and past email addresses |
| `PHONE_NUMBERS` | Linked phone numbers |
| `RICH_MEDIA` | URLs to photos, videos, documents |
| `PROFILE` | Biographical info, headline, location, websites, Twitter handles |
| `CONTACTS` | Previously imported contacts |

### Full Domain List

<details>
<summary>All 50+ available domains</summary>

- `ADS_CLICKED` - Ads clicked
- `MEMBER_FOLLOWING` - People followed
- `RICH_MEDIA` - Photos, videos, documents
- `SEARCHES` - Recent searches
- `ALL_COMMENTS` - Comments made
- `CONTACTS` - Imported contacts
- `Events` - Event attendance
- `INVITATIONS` - Sent/received invitations
- `PHONE_NUMBERS` - Linked phone numbers
- `CONNECTIONS` - 1st-degree connections
- `EMAIL_ADDRESSES` - Email addresses
- `INBOX` - Messages
- `PROFILE` - Basic profile info
- `SKILLS` - Profile skills
- `POSITIONS` - Job history
- `EDUCATION` - Education history
- `RECOMMENDATIONS` - Given/received
- `ENDORSEMENTS` - Given/received
- And many more...

</details>

## API Endpoints

### Member Snapshot API
Fetches data at a point in time.

```
GET https://api.linkedin.com/rest/memberSnapshotData?q=criteria&domain=CONNECTIONS
```

To fetch all domains, omit the `domain` parameter.

### Member Changelog API
Archives interactions from consent time (posts, comments, reactions). Limited to past 28 days.

## Authentication

1. Register app at [LinkedIn Developer Portal](https://www.linkedin.com/developers/)
2. Use OAuth 2.0 with scope: `r_dma_portability_self_serve`
3. User authorizes and generates access token
4. Call APIs with bearer token

## Implementation Plan

### Phase 1: OAuth Integration
- Add "Connect LinkedIn" button to Settings page
- Implement OAuth 2.0 flow with `r_dma_portability_self_serve` scope
- Store access token securely (encrypted in database)

### Phase 2: Initial Import
- Call Member Snapshot API for `CONNECTIONS`, `PROFILE`, `RICH_MEDIA`
- Parse response and match against existing contacts by email
- Create new contacts for unmatched connections
- Download and store profile photos via Active Storage

### Phase 3: Enrichment
- For existing contacts, update with LinkedIn data (name, job title, company)
- Link contacts to companies (create if needed)
- Store LinkedIn profile URL for reference

### Phase 4: Sync (Optional)
- Periodic re-sync via changelog API
- Track connection changes (new connections, job changes)

## Database Changes Needed

```ruby
# Migration: add_linkedin_fields_to_users
add_column :users, :linkedin_access_token, :string  # encrypted
add_column :users, :linkedin_token_expires_at, :datetime
add_column :users, :linkedin_member_id, :string

# Migration: add_linkedin_fields_to_contacts
add_column :contacts, :linkedin_url, :string
add_column :contacts, :linkedin_member_id, :string
add_column :contacts, :avatar, :string  # Active Storage attachment
```

## Gem Dependencies

```ruby
gem 'oauth2'  # OAuth 2.0 client
```

## References

- [Member Portability APIs Overview](https://learn.microsoft.com/en-us/linkedin/dma/member-data-portability/?view=li-dma-data-portability-2025-11)
- [Member Snapshot API](https://learn.microsoft.com/en-us/linkedin/dma/member-data-portability/member-data-portability-member)
- [Snapshot Domains List](https://learn.microsoft.com/en-us/linkedin/dma/member-data-portability/shared/snapshot-domain?view=li-dma-data-portability-2025-11)
- [DMA Portability API Terms](https://www.linkedin.com/legal/l/portability-api-terms)
- [LinkedIn Help: Member Portability APIs](https://www.linkedin.com/help/linkedin/answer/a6214075)

## Why This Works (Legal Basis)

The Digital Markets Act (EU 2022/1925) requires "gatekeepers" like LinkedIn to provide data portability. This is not scraping or ToS violation - it's a legal right for EU/EEA/Switzerland residents to access their own data programmatically.

## Comparison with Other Methods

| Method | Connections | Emails | Photos | ToS Compliant |
|--------|-------------|--------|--------|---------------|
| Manual CSV Export | Name, company | Mostly hidden | No | Yes |
| Partner API (Sales Nav) | Full | Yes | Yes | Yes (expensive) |
| Scraping | Full | Maybe | Yes | **No** |
| **DMA Portability API** | Full | Yes | Yes | **Yes** |
