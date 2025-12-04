# Ruby on Rails Best Practices: Lessons from Basecamp's Fizzy

This guide documents patterns and best practices extracted from Basecamp/37signals' Fizzy codebase - a production kanban-style project management application.

---

## Table of Contents
1. [Multi-Tenancy Architecture (Deep Dive)](#1-multi-tenancy-architecture)
2. [Concerns & Composition (Deep Dive)](#2-concerns--composition)
3. [Hotwire/Turbo Patterns (Deep Dive)](#3-hotwireturbo-patterns)
4. [Testing Approach (Deep Dive)](#4-testing-approach)
5. [Other Patterns](#5-other-patterns)
6. [Key Takeaways](#6-key-takeaways)

---

## 1. Multi-Tenancy Architecture

### URL Path-Based Tenancy
Fizzy uses middleware to extract account ID from URL paths (no subdomains needed):

```ruby
# config/initializers/tenanting/account_slug.rb
class AccountSlug::Extractor
  def call(env)
    request = ActionDispatch::Request.new(env)

    if request.path_info =~ /\A(\/\d{7,})/
      # Move account prefix from PATH_INFO to SCRIPT_NAME
      request.script_name = $1           # "/1234567"
      request.path_info = $'.empty? ? "/" : $'  # "/boards/123"
      env["fizzy.external_account_id"] = $2.to_i
    end

    Current.with_account(account) { @app.call(env) }
  end
end
```

**How SCRIPT_NAME works:**
- URL: `GET /1234567/boards/123`
- Middleware sets: `script_name = "/1234567"`, `path_info = "/boards/123"`
- Rails thinks app is "mounted" at `/1234567`
- Routes don't need account prefix - they work naturally
- URL helpers automatically include script_name in generated URLs

### CurrentAttributes for Context

```ruby
# app/models/current.rb
class Current < ActiveSupport::CurrentAttributes
  attribute :session, :user, :account
  attribute :http_method, :request_id, :user_agent, :ip_address

  def session=(value)
    super(value)
    # Auto-derive user for current account when session is set
    self.user = identity.users.find_by(account: account) if value.present? && account.present?
  end

  def with_account(value, &)
    with(account: value, &)
  end
end
```

### Model Scoping via Lambda Defaults

**NO default_scope** - explicit isolation via association defaults:

```ruby
# app/models/board.rb
belongs_to :account, default: -> { creator.account }

# app/models/card.rb
belongs_to :account, default: -> { board.account }

# app/models/comment.rb
belongs_to :account, default: -> { card.account }

# app/models/tag.rb (root level)
belongs_to :account, default: -> { Current.account }
```

**Pattern**: Account ID cascades through relationships. Only root-level models use `Current.account`.

### Background Job Context Propagation

```ruby
# config/initializers/active_job.rb
module FizzyActiveJobExtensions
  def initialize(...)
    super
    @account = Current.account  # Capture at enqueue time
  end

  def serialize
    super.merge("account" => @account&.to_gid)  # Store as GlobalID
  end

  def deserialize(job_data)
    super
    @account = GlobalID::Locator.locate(job_data["account"])
  end

  def perform_now
    Current.with_account(account) { super }  # Restore context at runtime
  end
end

ActiveSupport.on_load(:active_job) { prepend FizzyActiveJobExtensions }
```

**Result**: Jobs never need explicit `account_id` parameter - context flows automatically.

### Multi-Account Authentication

```ruby
# app/models/identity.rb - Global (email-based)
class Identity < ApplicationRecord
  has_many :users  # Can have users in multiple accounts
  has_many :accounts, through: :users
end

# app/models/user.rb - Account-scoped
class User < ApplicationRecord
  belongs_to :account
  belongs_to :identity, optional: true
end
```

**Flow**: Session is global (identity-based), but user is auto-derived per account.

---

## 2. Concerns & Composition

### Directory Structure (72 total concerns)

```
app/models/concerns/           (7 files)  - Shared protocols
app/models/card/               (24 files) - Card-specific
app/models/user/               (16 files) - User-specific
app/models/board/              (8 files)  - Board-specific
app/controllers/concerns/      (15 files) - Controller concerns
```

### Naming Conventions

| Pattern | Examples |
|---------|----------|
| **-able** (capabilities) | `Assignable`, `Closeable`, `Searchable`, `Watchable` |
| **-ible** | `Accessible` |
| **Action verbs** | `Mentions`, `Attachments` |
| **States** | `Statuses`, `Golden` |

### Concern Anatomy Patterns

**Pattern A: Simple Delegation (4-10 lines)**
```ruby
# app/models/concerns/push_notifiable.rb
module PushNotifiable
  extend ActiveSupport::Concern

  included do
    after_create_commit :push_notification_later
  end

  private
    def push_notification_later
      PushNotificationJob.perform_later(self)
    end
end
```

**Pattern B: Association + Scopes (15-30 lines)**
```ruby
# app/models/card/closeable.rb
module Card::Closeable
  extend ActiveSupport::Concern

  included do
    has_one :closure, dependent: :destroy

    scope :closed, -> { joins(:closure) }
    scope :open, -> { where.missing(:closure) }
  end

  def closed?
    closure.present?
  end

  def close(user: Current.user)
    transaction do
      create_closure!(user: user)
      track_event :closed, creator: user
    end
  end
end
```

**Pattern C: Template Method (Base + Override)**
```ruby
# app/models/concerns/eventable.rb (base)
module Eventable
  def track_event(action, **particulars)
    board.events.create!(action: action, eventable: self, **particulars) if should_track_event?
  end

  def should_track_event?
    true  # Override in model-specific concern
  end
end

# app/models/card/eventable.rb (override)
module Card::Eventable
  include ::Eventable

  def should_track_event?
    published?  # Only track events for published cards
  end
end
```

### Cross-Concern Dependencies

Concerns call methods from other concerns via loose coupling:

```ruby
# app/models/card/postponable.rb
def postpone(user: Current.user)
  transaction do
    send_back_to_triage(skip_event: true)  # From Triageable
    reopen                                   # From Closeable
    activity_spike&.destroy                  # From Stallable
    track_event :postponed                   # From Eventable
  end
end
```

### When to Extract to Concern

| Trigger | Location |
|---------|----------|
| 2+ models share behavior | `app/models/concerns/` |
| 40+ lines in single model | `app/models/{model}/` |
| Clear domain boundary | Model-specific subdirectory |
| Cross-cutting controller logic | `app/controllers/concerns/` |

---

## 3. Hotwire/Turbo Patterns

### Turbo Frame Naming

```erb
<%# Simple resource frame %>
<%= turbo_frame_tag @card, :edit %>

<%# Lazy-loaded frame with morph %>
<%= turbo_frame_tag card, :assignment,
    src: new_card_assignment_path(card),
    loading: :lazy,
    refresh: "morph" %>

<%# Container frame %>
<%= turbo_frame_tag :cards_container do %>
```

### Turbo Stream Subscriptions

```erb
<%# app/views/cards/show.html.erb %>
<%= turbo_stream_from @card %>           <%# Card updates %>
<%= turbo_stream_from @card, :activity %> <%# Activity stream %>

<%# app/views/boards/show.html.erb %>
<%= turbo_stream_from @board %>

<%# Dynamic subscription based on filter %>
<% filter.boards.each do |board| %>
  <%= turbo_stream_from board %>
<% end %>
```

### Turbo Stream Responses

```erb
<%# app/views/cards/comments/create.turbo_stream.erb %>
<%= turbo_stream.before [card, :new_comment], partial: "comment", locals: { comment: @comment } %>
<%= turbo_stream.update [card, :new_comment], partial: "new_comment" %>

<%# With morphing %>
<%= turbo_stream.replace dom_id(@card, :container),
    partial: "cards/container",
    method: :morph,
    locals: { card: @card.reload } %>
```

### Global Morph Configuration

```erb
<%# app/views/layouts/shared/_head.html.erb %>
<% turbo_refreshes_with method: :morph, scroll: :preserve %>
<meta name="view-transition" content="same-origin">
```

### Stimulus Controller Patterns

**Values, Targets, Classes:**
```javascript
// app/javascript/controllers/dialog_controller.js
export default class extends Controller {
  static targets = ["dialog"]
  static values = { modal: { type: Boolean, default: false } }
  static classes = ["open"]

  open() {
    this.dialogTarget.showModal()
    this.loadLazyFrames()  // Convert lazy frames to eager on open
  }

  loadLazyFrames() {
    this.dialogTarget.querySelectorAll("turbo-frame")
      .forEach(frame => frame.loading = "eager")
  }
}
```

**Multi-Controller Composition:**
```erb
<%= tag.div data: {
  controller: "collapsible-columns drag-and-drop navigable-list",
  collapsible_columns_board_value: board.id,
  drag_and_drop_dragged_item_class: "dragged",
  action: "
    keydown->navigable-list#navigate
    dragstart->drag-and-drop#dragStart
    drop->drag-and-drop#drop"
} do %>
```

**Private Fields for Encapsulation:**
```javascript
export default class extends Controller {
  #timer

  change(event) {
    if (!this.#dirty) this.#scheduleSave()
  }

  #scheduleSave() {
    this.#timer = setTimeout(() => this.#save(), 3000)
  }

  get #dirty() { return !!this.#timer }
}
```

### JavaScript Helpers

```javascript
// app/javascript/helpers/timing_helpers.js
export function debounce(fn, delay = 1000) {
  let timeoutId
  return (...args) => {
    clearTimeout(timeoutId)
    timeoutId = setTimeout(() => fn.apply(this, args), delay)
  }
}

export function nextFrame() {
  return new Promise(requestAnimationFrame)
}

// app/javascript/helpers/scroll_helpers.js
export async function keepingScrollPosition(element, promise) {
  const original = element.getBoundingClientRect()
  await promise
  const current = element.getBoundingClientRect()
  findNearestScrollableAncestor(element).scrollTop += current.top - original.top
}
```

---

## 4. Testing Approach

### Pure Fixtures (No Factories)

```yaml
# test/fixtures/users.yml
david:
  id: <%= ActiveRecord::FixtureSet.identify("david", :uuid) %>
  name: David
  role: member
  identity: david
  account: 37s

kevin:
  id: <%= ActiveRecord::FixtureSet.identify("kevin", :uuid) %>
  name: Kevin
  role: admin
  identity: kevin
  account: 37s
```

### Deterministic UUID Generation for Fixtures

```ruby
# test/test_helper.rb
def generate_fixture_uuid(label)
  # UUIDv7 with deterministic timestamp from CRC32 hash
  # Ensures fixtures are always "older" than runtime records
  fixture_int = Zlib.crc32("fixtures/#{label}") % (2**30 - 1)
  base_time = Time.utc(2024, 1, 1)
  timestamp = base_time + (fixture_int / 1000.0)
  uuid_v7_with_timestamp(timestamp, label)
end
```

**Benefit**: `.first`/`.last` work correctly in tests.

### Test Helper Configuration

```ruby
# test/test_helper.rb
module ActiveSupport
  class TestCase
    parallelize(workers: :number_of_processors)
    fixtures :all

    include SessionTestHelper, CardTestHelper, ActionTextTestHelper

    setup do
      Current.account = accounts("37s")  # Default tenant context
    end

    teardown do
      Current.clear_all
    end
  end
end
```

### Session Test Helper

```ruby
# test/test_helpers/session_test_helper.rb
def sign_in_as(identity)
  identity.send_magic_link
  magic_link = identity.magic_links.last
  untenanted { post session_magic_link_url, params: { code: magic_link.code } }
end

def untenanted(&block)
  original = integration_session.default_url_options[:script_name]
  integration_session.default_url_options[:script_name] = ""
  yield
ensure
  integration_session.default_url_options[:script_name] = original
end

def with_current_user(user)
  old_session = Current.session
  Current.session = Session.new(identity: user.identity)
  yield
ensure
  Current.session = old_session
end
```

### Controller Test Pattern

```ruby
# test/controllers/cards_controller_test.rb
class CardsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as :kevin }

  test "update with turbo stream" do
    patch card_path(cards(:logo)), as: :turbo_stream, params: {
      card: { title: "New Title", tag_ids: [tags(:mobile).id] }
    }
    assert_response :success
    assert_equal "New Title", cards(:logo).reload.title
  end

  test "authorization" do
    boards(:writebook).accesses.revoke_from users(:kevin)
    get card_path(cards(:logo))
    assert_response :not_found
  end
end
```

### System Test Pattern

```ruby
# test/system/smoke_test.rb
class SmokeTest < ApplicationSystemTestCase
  test "create a card" do
    sign_in_as(users(:david))
    visit board_url(boards(:writebook))
    click_on "Add a card"
    fill_in "card_title", with: "Hello, world!"
    click_on "Create card"
    assert_selector "h3", text: "Hello, world!"
  end

  private
    def sign_in_as(user)
      visit session_transfer_url(user.identity.transfer_id, script_name: nil)
    end
end
```

### CI Pipeline

```ruby
# config/ci.rb
CI.run do
  step "Style: Ruby", "bin/rubocop"
  step "Security: Gem audit", "bin/bundler-audit check --update"
  step "Security: Brakeman", "bin/brakeman --quiet --exit-on-warn"
  step "Tests: Unit", "bin/rails test"
  step "Tests: System", "PARALLEL_WORKERS=1 bin/rails test:system"
end
```

**Note**: System tests run with `PARALLEL_WORKERS=1` (Capybara/Selenium doesn't parallelize).

---

## 5. Other Patterns

### After-Commit Callbacks

```ruby
# Safe for async jobs - runs after transaction commits
after_save_commit :create_mentions_later
after_create_commit :create_in_search_index
after_destroy_commit :remove_from_search_index
```

### Separate Models Over STI

```ruby
# Instead of type column on Card:
Card::NotNow      # has_one :not_now
Card::Goldness    # has_one :goldness
Closure           # has_one :closure
```

### Enums with Custom Scopes

```ruby
enum :role, %i[owner admin member system].index_by(&:itself), scopes: false

# Then define custom scopes
scope :admin, -> { where(active: true, role: %i[owner admin]) }
```

### Polymorphic Event Tracking

```ruby
# Any model can track events
module Eventable
  def track_event(action, **particulars)
    board.events.create!(
      action: "#{eventable_prefix}_#{action}",
      eventable: self,
      particulars: particulars
    )
  end
end
```

### Form Objects

```ruby
class Signup
  include ActiveModel::Model
  include ActiveModel::Validations

  with_options on: :completion do
    validates_presence_of :full_name
  end
end
```

---

## 6. Key Takeaways

| Pattern | Basecamp Approach |
|---------|-------------------|
| **Multi-tenancy** | URL path prefix via middleware, SCRIPT_NAME trick |
| **Request Context** | `CurrentAttributes` with auto-derivation |
| **Model Isolation** | Lambda defaults on `belongs_to`, NO default_scope |
| **Job Context** | Auto-serialize/restore via GlobalID |
| **Code Organization** | 72 concerns across 7 directories |
| **Concern Extraction** | At 40+ lines or 2+ models sharing |
| **Frontend** | Turbo Frames + Streams + Stimulus, no ViewComponent |
| **Morph Strategy** | Global `turbo_refreshes_with method: :morph` |
| **Testing** | Pure fixtures, deterministic UUIDs, parallel unit tests |
| **Authentication** | Passwordless magic links, global identity + scoped user |

### Philosophy

1. **Embrace Rails conventions** - Don't fight the framework
2. **Composition over inheritance** - Concerns > STI
3. **Explicit over implicit** - No default_scope, separate state models
4. **Simplicity** - Importmaps > Webpack, helpers > ViewComponent
5. **Context propagation** - CurrentAttributes flows through requests and jobs
6. **Safety first** - after_commit callbacks, scoped queries via associations

---

*Extracted from Fizzy, a production Rails application by Basecamp/37signals.*
