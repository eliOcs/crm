# Email Integration Feature Spec

## Overview

This document outlines an email integration approach that works without requiring IT/OAuth approval. It uses email forwarding and BCC capture to feed emails into Mercurio CRM, inspired by [Salesforce's Email to Salesforce](https://help.salesforce.com/s/articleView?id=sales.email_my_email_2_sfdc.htm&language=en_US&type=5) feature.

**Goal:** Provide a low-friction way for users to get emails into the CRM while the full Microsoft Graph API integration awaits IT approval.

## Architecture

Self-hosted approach using Postfix on the same server. No external dependencies, no data ping-ponging between services, portable across cloud providers.

```
+-----------------------------------------------------------------------+
|                         USER'S EMAIL CLIENT                           |
|                      (Outlook, Gmail, etc.)                           |
+---------------+---------------------------------+---------------------+
                |                                 |
        +-------v-------+                 +-------v-------+
        |   INBOUND     |                 |   OUTBOUND    |
        |  (Received)   |                 |    (Sent)     |
        +-------+-------+                 +-------+-------+
                |                                 |
    Mail rule forwards                    User adds BCC
    to unique address                     to unique address
                |                                 |
                +-----------------+---------------+
                                  |
                                  v
+-----------------------------------------------------------------------+
|                     MERCURIO SERVER (EC2/VPS)                         |
|                                                                       |
|  +---------------------------------------------------------------+   |
|  |                    Postfix (Port 25)                          |   |
|  |                                                               |   |
|  |  MX: inbox.mercuriocrm.es -> this server                      |   |
|  |  Receives: *@inbox.mercuriocrm.es                             |   |
|  +-----------------------------+---------------------------------+   |
|                                |                                     |
|                          Pipes email to                              |
|                                |                                     |
|                                v                                     |
|  +---------------------------------------------------------------+   |
|  |                  Rails (ActionMailbox)                        |   |
|  |                                                               |   |
|  |  bin/rails action_mailbox:ingress:postfix                     |   |
|  |    |-- Parse email (Mail gem)                                 |   |
|  |    |-- Identify user by recipient token                       |   |
|  |    |-- Detect if forwarded -> extract original headers        |   |
|  |    |-- Store in same SQLite database                          |   |
|  |    |-- Match contacts by email addresses                      |   |
|  |    +-- Run EmailEnrichmentService (LLM extraction)            |   |
|  +---------------------------------------------------------------+   |
+-----------------------------------------------------------------------+
```

**Benefits of self-hosted:**
- No external service dependencies
- Data stays on your server (no webhook round-trips)
- Works with any cloud provider (portable)
- No per-email costs
- Lower latency (direct pipe to Rails)

## User Experience

### Setup (One-time)

1. User navigates to **Settings -> Email Integration**
2. System displays their unique Mercurio email address:
   ```
   Your Mercurio address: anna.puchal.x7k9@inbox.mercuriocrm.es
   ```
3. User copies address and sets up:
   - **For received emails:** Mail rule in Outlook/Gmail to forward to this address
   - **For sent emails:** Add address to BCC (or create contact named "Mercurio")

### Daily Use

- **Received emails:** Automatically forwarded by mail rule -> appear in CRM
- **Sent emails:** User adds BCC -> email logged in CRM
- **Selective logging:** User can forward individual emails manually

### Viewing in CRM

- Emails appear in contact/company timeline
- Tasks extracted via LLM
- "Unresolved" emails (no contact match) shown in separate queue

## Technical Implementation

### Phase 1: Server Infrastructure

#### DNS Configuration

```
; MX record for inbound email subdomain
inbox.mercuriocrm.es.  IN  MX  10  mercuriocrm.es.

; A record pointing to server
mercuriocrm.es.        IN  A   52.30.167.17
```

#### Port 25 Access

Most cloud providers block port 25 by default to prevent spam:

- **AWS EC2:** Request port 25 unblock via support ticket (usually approved for legitimate use)
- **DigitalOcean:** Unblocked by default after account age/verification
- **Hetzner:** Unblocked by default
- **Self-hosted/VPS:** Usually unblocked

#### Postfix Installation

```bash
# Install Postfix (Ubuntu/Debian)
apt-get install postfix

# Or on the Docker container
apk add postfix
```

#### Postfix Configuration

```conf
# /etc/postfix/main.cf

# Basic settings
myhostname = mercuriocrm.es
mydomain = mercuriocrm.es
myorigin = $mydomain

# Only accept mail for our inbound subdomain
mydestination =
virtual_mailbox_domains = inbox.mercuriocrm.es
virtual_transport = rails

# Security: only accept mail, don't relay
smtpd_relay_restrictions = permit_mynetworks, reject_unauth_destination

# Size limits
message_size_limit = 26214400  # 25MB
```

```conf
# /etc/postfix/master.cf

# Add this line to pipe emails to Rails
rails unix - n n - - pipe
  flags=DRXhu user=deploy argv=/home/deploy/crm/bin/rails action_mailbox:ingress:postfix
```

#### Kamal Integration

Add Postfix to the Docker deployment:

```yaml
# config/deploy.yml
accessories:
  postfix:
    image: boky/postfix  # or build custom
    host: 52.30.167.17
    port: "25:25"
    env:
      ALLOWED_SENDER_DOMAINS: inbox.mercuriocrm.es
    volumes:
      - /var/spool/postfix:/var/spool/postfix
```

Alternative: Run Postfix directly on host, outside Docker.

### Phase 2: Rails Integration

#### ActionMailbox Setup

```ruby
# Gemfile - ActionMailbox is included in Rails 8

# config/environments/production.rb
config.action_mailbox.ingress = :relay
config.action_mailbox.relay_password = Rails.application.credentials.action_mailbox_relay_password

# Generate password
# bin/rails credentials:edit
# action_mailbox_relay_password: <generate with SecureRandom.base58(32)>
```

#### Mailbox Routing

```ruby
# app/mailboxes/application_mailbox.rb
class ApplicationMailbox < ActionMailbox::Base
  routing all: :inbound_email
end
```

```ruby
# app/mailboxes/inbound_email_mailbox.rb
class InboundEmailMailbox < ApplicationMailbox
  def process
    user = find_user_by_recipient
    unless user
      logger.warn "No user found for recipient: #{mail.to}"
      return
    end

    email_record = create_email_record(user)
    EmailEnrichmentService.new(user).process_email_record(email_record)
  end

  private

  def find_user_by_recipient
    # Parse recipient: anna.puchal.x7k9@inbox.mercuriocrm.es
    recipient = mail.to&.first.to_s.downcase
    return nil unless recipient.end_with?("@inbox.mercuriocrm.es")

    local_part = recipient.split("@").first
    token = local_part.split(".").last
    User.find_by(inbound_email_token: token)
  end

  def create_email_record(user)
    # Detect if forwarded and extract original headers
    original = ForwardedEmailParser.parse(mail)

    user.emails.create!(
      subject: original[:subject] || mail.subject,
      from_address: original[:from] || extract_address(mail.from),
      to_addresses: original[:to] || mail.to&.map { |a| extract_address(a) },
      body_plain: original[:body_plain] || mail.text_part&.decoded,
      body_html: original[:body_html] || mail.html_part&.decoded,
      sent_at: original[:date] || mail.date,
      source_type: original[:forwarded] ? "forwarded" : "direct"
    )
  end

  def extract_address(addr)
    parsed = Mail::Address.new(addr)
    { email: parsed.address, name: parsed.display_name }
  rescue
    { email: addr.to_s, name: nil }
  end
end
```

#### User Model Addition

```ruby
# Migration
class AddInboundEmailTokenToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :inbound_email_token, :string
    add_column :users, :approved_sender_addresses, :json, default: []
    add_index :users, :inbound_email_token, unique: true
  end
end
```

```ruby
# app/models/user.rb
class User < ApplicationRecord
  before_create :generate_inbound_email_token

  def inbound_email_address
    "#{email_prefix}.#{inbound_email_token}@inbox.mercuriocrm.es"
  end

  def regenerate_inbound_email_token!
    generate_inbound_email_token
    save!
  end

  private

  def email_prefix
    email_address.split("@").first.parameterize.first(20)
  end

  def generate_inbound_email_token
    self.inbound_email_token = SecureRandom.alphanumeric(8).downcase
  end
end
```

### Phase 3: Forwarded Email Parsing

Forwarded emails have different formats. The challenge is extracting the original sender/recipients.

#### Approach 1: Forward as Attachment (Best)

Per [SAP Community best practices](https://community.sap.com/t5/crm-and-cx-blogs-by-members/advanced-inbound-email-handling/ba-p/13191847), forwarding as attachment preserves original headers as a MIME object.

```ruby
# app/services/forwarded_email_parser.rb
class ForwardedEmailParser
  def self.parse(mail)
    new(mail).parse
  end

  def initialize(mail)
    @mail = mail
  end

  def parse
    # Try attachment method first (most reliable)
    if (attached = extract_from_attachment)
      return attached.merge(forwarded: true)
    end

    # Fall back to body parsing
    if (from_body = extract_from_body)
      return from_body.merge(forwarded: true)
    end

    # Not forwarded, use original
    { forwarded: false }
  end

  private

  def extract_from_attachment
    attachment = @mail.attachments.find do |a|
      a.content_type&.start_with?("message/rfc822")
    end
    return nil unless attachment

    original = Mail.new(attachment.decoded)
    {
      subject: original.subject,
      from: extract_address(original.from),
      to: original.to&.map { |a| extract_address(a) },
      date: original.date,
      body_plain: original.text_part&.decoded || original.body.decoded,
      body_html: original.html_part&.decoded
    }
  end

  def extract_from_body
    body = @mail.text_part&.decoded || @mail.body.decoded
    return nil unless body

    # Try different forwarding formats
    parsed = parse_outlook_forward(body) ||
             parse_gmail_forward(body) ||
             parse_generic_forward(body)

    return nil unless parsed

    {
      subject: parsed[:subject],
      from: { email: parsed[:from_email], name: parsed[:from_name] },
      to: parsed[:to] ? [{ email: parsed[:to], name: nil }] : nil,
      date: parsed[:date],
      body_plain: parsed[:body],
      body_html: nil
    }
  end

  OUTLOOK_FORWARD = /
    -+\s*Original\s+Message\s*-+\s*
    From:\s*(?<from>.+?)\n
    (?:Sent:\s*(?<date>.+?)\n)?
    To:\s*(?<to>.+?)\n
    (?:Cc:\s*.+?\n)?
    Subject:\s*(?<subject>.+?)\n
    \n
    (?<body>.*)
  /mix

  GMAIL_FORWARD = /
    -+\s*Forwarded\s+message\s*-+\s*
    From:\s*(?<from>.+?)\n
    Date:\s*(?<date>.+?)\n
    Subject:\s*(?<subject>.+?)\n
    To:\s*(?<to>.+?)\n
    \n
    (?<body>.*)
  /mix

  def parse_outlook_forward(body)
    match = body.match(OUTLOOK_FORWARD)
    return nil unless match

    from_parsed = parse_from_field(match[:from])
    {
      from_email: from_parsed[:email],
      from_name: from_parsed[:name],
      to: match[:to]&.strip,
      subject: match[:subject]&.strip,
      date: parse_date(match[:date]),
      body: match[:body]
    }
  end

  def parse_gmail_forward(body)
    match = body.match(GMAIL_FORWARD)
    return nil unless match

    from_parsed = parse_from_field(match[:from])
    {
      from_email: from_parsed[:email],
      from_name: from_parsed[:name],
      to: match[:to]&.strip,
      subject: match[:subject]&.strip,
      date: parse_date(match[:date]),
      body: match[:body]
    }
  end

  def parse_generic_forward(body)
    # Look for quoted headers at start of body
    return nil unless body.match?(/^>\s*From:/i)
    # TODO: Implement generic parsing
    nil
  end

  def parse_from_field(from_str)
    addr = Mail::Address.new(from_str.strip)
    { email: addr.address, name: addr.display_name }
  rescue
    if from_str =~ /<(.+?)>/
      { email: $1, name: from_str.split("<").first.strip }
    else
      { email: from_str.strip, name: nil }
    end
  end

  def parse_date(date_str)
    return nil unless date_str
    Time.parse(date_str.strip)
  rescue
    nil
  end

  def extract_address(addr)
    parsed = Mail::Address.new(Array(addr).first)
    { email: parsed.address, name: parsed.display_name }
  rescue
    { email: addr.to_s, name: nil }
  end
end
```

### Phase 4: Contact Matching

Similar to Salesforce's approach:

```ruby
# app/services/email_contact_matcher.rb
class EmailContactMatcher
  MAX_ADDRESSES = 50  # Salesforce's limit

  def initialize(user)
    @user = user
  end

  def match(email_addresses)
    addresses = Array(email_addresses).first(MAX_ADDRESSES)
    matched = []
    unmatched = []

    addresses.each do |addr|
      email = addr.is_a?(Hash) ? addr[:email] : addr
      next unless email

      contact = @user.contacts.find_by(email: email.downcase)
      if contact
        matched << contact
      else
        unmatched << email
      end
    end

    { matched: matched.uniq, unmatched: unmatched.uniq }
  end
end
```

### Phase 5: Unresolved Items Queue

Emails that don't match any contact go to an "Unresolved" queue:

```ruby
# Email model
class Email < ApplicationRecord
  scope :unresolved, -> { where(contact_id: nil) }
  scope :resolved, -> { where.not(contact_id: nil) }
end
```

UI shows unresolved emails with options to:
- Create new contact from email address
- Link to existing contact
- Ignore/archive

## Security Considerations

### Sender Verification

Like Salesforce's "My Acceptable Email Addresses":
- User configures which email addresses they send from
- Emails from unrecognized senders are rejected or flagged

```ruby
def verify_sender(user, from_address)
  return true if user.approved_sender_addresses.include?(from_address.downcase)
  return true if from_address.downcase == user.email_address

  # Log warning, still process but flag
  false
end
```

### Rate Limiting

```ruby
# In InboundEmailMailbox
def process
  user = find_user_by_recipient
  return unless user

  # Rate limit: 100 emails per hour per user
  cache_key = "inbound_email_rate:#{user.id}"
  count = Rails.cache.increment(cache_key, 1, expires_in: 1.hour, initial: 0)

  if count > 100
    logger.warn "Rate limit exceeded for user #{user.id}"
    return
  end

  # ... rest of processing
end
```

### Token Rotation

Allow users to regenerate their inbound email token if compromised:

```ruby
# In settings controller
def regenerate_email_token
  Current.user.regenerate_inbound_email_token!
  redirect_to settings_path, notice: "Email address regenerated"
end
```

### Postfix Security

```conf
# /etc/postfix/main.cf additions

# TLS for incoming connections (optional but recommended)
smtpd_tls_cert_file = /etc/letsencrypt/live/mercuriocrm.es/fullchain.pem
smtpd_tls_key_file = /etc/letsencrypt/live/mercuriocrm.es/privkey.pem
smtpd_tls_security_level = may

# Limit connection rates
smtpd_client_connection_rate_limit = 10
smtpd_client_message_rate_limit = 30

# Reject obvious spam
smtpd_helo_required = yes
smtpd_helo_restrictions = reject_invalid_helo_hostname
```

## Limitations

Per [Outreach's analysis](https://www.outreach.io/resources/blog/bcc-to-salesforce-breakdown-how-to-setup-and-3-drawbacks):

1. **User friction:** Requires manual BCC for outbound (unless mail rule handles it)
2. **Incomplete threads:** If user forgets BCC, that email is missing
3. **No open/click tracking:** Unlike integrated solutions
4. **Forwarding format variations:** Parsing original headers is fragile
5. **Delayed processing:** Not real-time like Graph API webhooks

## Comparison: Forwarding vs Graph API

| Aspect | Email Forwarding | Microsoft Graph API |
|--------|------------------|---------------------|
| IT Approval | Not required | Required |
| Setup complexity | User mail rules | OAuth flow |
| Real-time | Near-instant (SMTP) | Instant webhooks |
| Reliability | Depends on forwarding | Direct API access |
| Sent emails | BCC required | Automatic capture |
| Email sending | Not supported | Full support |
| Open/click tracking | No | Possible |
| Infrastructure | Self-hosted Postfix | Cloud dependency |
| Portability | Any provider | Azure-specific |

## Migration Path

When Graph API is approved:
1. Keep forwarding as fallback option
2. Add Graph integration as "premium" option
3. Users can switch in settings
4. Both can coexist (some users may prefer forwarding)

## Implementation Phases

### MVP (Phase 1-2)
- [ ] Request AWS port 25 unblock
- [ ] Install and configure Postfix
- [ ] DNS MX record for inbox.mercuriocrm.es
- [ ] ActionMailbox relay ingress setup
- [ ] User inbound email token migration
- [ ] Basic email parsing (non-forwarded)
- [ ] Settings UI to show/copy address

### Enhanced (Phase 3-4)
- [ ] ForwardedEmailParser service
- [ ] Forward-as-attachment parsing
- [ ] Forward body parsing (Outlook, Gmail)
- [ ] Contact matching service
- [ ] Unresolved items queue UI

### Polish (Phase 5)
- [ ] Approved sender addresses config
- [ ] Rate limiting
- [ ] Token rotation UI
- [ ] Mail rule setup instructions per client (Outlook, Gmail)
- [ ] Postfix TLS configuration

## Fallback: Cloud Services

If self-hosted Postfix proves problematic, these are alternatives:

| Service | Free Tier | Webhook Support | Notes |
|---------|-----------|-----------------|-------|
| Mailgun | 1,000/month | Yes | Simple setup |
| Postmark | 100/month | Yes | Good deliverability |
| SendGrid | Limited | Yes | Complex pricing |
| AWS SES | ~$0 | Via S3/Lambda | AWS lock-in |

ActionMailbox has built-in ingresses for Mailgun, Postmark, SendGrid, and Amazon SES.

## References

- [Salesforce Email to Salesforce](https://help.salesforce.com/s/articleView?id=sales.email_my_email_2_sfdc.htm&language=en_US&type=5)
- [Salesforce BCC Guide - PersistIQ](https://www.persistiq.com/salesforce-bcc-email-a-comprehensive-guide/)
- [BCC to Salesforce Drawbacks - Outreach](https://www.outreach.io/resources/blog/bcc-to-salesforce-breakdown-how-to-setup-and-3-drawbacks)
- [Forward as Attachment Best Practice - SAP Community](https://community.sap.com/t5/crm-and-cx-blogs-by-members/advanced-inbound-email-handling/ba-p/13191847)
- [Rails ActionMailbox Guide](https://guides.rubyonrails.org/action_mailbox_basics.html)
- [Postfix Documentation](http://www.postfix.org/documentation.html)
