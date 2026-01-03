# Modern Rails 8+ Best Practices

Rails 8+ with SQLite and Hotwire represents a paradigm shift toward simplicity without sacrificing power. This guide documents current best practices based on Basecamp/37signals' production patterns and official Rails conventions.

---

## Table of Contents

1. [Philosophy](#philosophy)
2. [Multi-Tenancy Architecture](#multi-tenancy-architecture)
3. [Concerns & Composition](#concerns--composition)
4. [Active Record Best Practices](#active-record-best-practices)
5. [Hotwire Patterns](#hotwire-patterns)
6. [Controllers & Views](#controllers--views)
7. [Testing](#testing)
8. [SQLite Production Configuration](#sqlite-production-configuration)
9. [Background Jobs](#background-jobs)
10. [Security](#security)
11. [Performance](#performance)
12. [Asset Management](#asset-management)
13. [Deployment](#deployment)

---

## Philosophy

| Principle | Approach |
|-----------|----------|
| **Embrace Rails conventions** | Don't fight the framework |
| **Composition over inheritance** | Concerns > STI |
| **Explicit over implicit** | No default_scope, separate state models |
| **Simplicity** | Importmaps > Webpack, helpers > ViewComponent |
| **Context propagation** | CurrentAttributes flows through requests and jobs |
| **Safety first** | after_commit callbacks, scoped queries via associations |

---

## Multi-Tenancy Architecture

### CurrentAttributes for Request Context

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

**NO default_scope** - use explicit isolation via association defaults:

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
module TenantedActiveJobExtensions
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

ActiveSupport.on_load(:active_job) { prepend TenantedActiveJobExtensions }
```

**Result**: Jobs never need explicit `account_id` parameter - context flows automatically.

---

## Concerns & Composition

### Directory Structure

```
app/models/concerns/           - Shared protocols (2+ models)
app/models/card/               - Card-specific concerns
app/models/user/               - User-specific concerns
app/controllers/concerns/      - Controller concerns
```

### Naming Conventions

| Pattern | Examples |
|---------|----------|
| **-able** (capabilities) | `Assignable`, `Closeable`, `Searchable`, `Watchable` |
| **-ible** | `Accessible` |
| **Action verbs** | `Mentions`, `Attachments` |
| **States** | `Statuses`, `Golden` |

### When to Extract to Concern

| Trigger | Location |
|---------|----------|
| 2+ models share behavior | `app/models/concerns/` |
| 40+ lines in single model | `app/models/{model}/` |
| Clear domain boundary | Model-specific subdirectory |
| Cross-cutting controller logic | `app/controllers/concerns/` |

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

---

## Active Record Best Practices

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

### Normalizes for Attribute Cleaning

```ruby
class User < ApplicationRecord
  normalizes :email, with: -> email { email.strip.downcase }
  normalizes :phone, with: -> phone { phone.delete("^0-9") }
end
```

### Association Configuration

Critical association options:

- `dependent: :destroy` - calls destroy (triggers callbacks, slower)
- `dependent: :delete_all` - direct SQL DELETE (faster, skips callbacks)
- `dependent: :nullify` - sets foreign key to NULL
- `dependent: :restrict_with_exception` - prevents deletion
- `counter_cache: true` - avoid N+1 COUNT queries
- `inverse_of:` - ensures both sides reference same in-memory object
- `touch: true` - invalidate parent cache when child changes

### Query Optimization

```ruby
# ❌ BAD: N+1 queries
authors = Author.all
authors.each { |author| puts author.books.count }

# ✅ GOOD: 2 queries total
authors = Author.includes(:books).all
authors.each { |author| puts author.books.size }

# Filter by association without loading data
Author.joins(:books).where(books: { published: true }).distinct
```

Use:
- `pluck(:column)` for direct SQL column selection
- `find_each(batch_size:)` for memory-efficient iteration
- `exists?` for fast boolean checks

### After-Commit Callbacks

```ruby
# Safe for async jobs - runs after transaction commits
after_save_commit :create_mentions_later
after_create_commit :create_in_search_index
after_destroy_commit :remove_from_search_index
```

**Use `after_commit` for side effects** like file operations or external API calls.

### Service Objects for Complex Operations

Extract complex operations spanning multiple models:

```ruby
class Users::RegistrationService
  def call(params)
    User.transaction do
      user = User.create!(params)
      Profile.create!(user: user)
      Team.create!(owner: user)
      SubscriptionMailer.welcome(user).deliver_later
      user
    end
  end
end
```

---

## Hotwire Patterns

### Global Morph Configuration

```erb
<%# app/views/layouts/shared/_head.html.erb %>
<% turbo_refreshes_with method: :morph, scroll: :preserve %>
<meta name="view-transition" content="same-origin">
```

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

<%# Dynamic subscription based on filter %>
<% filter.boards.each do |board| %>
  <%= turbo_stream_from board %>
<% end %>
```

### Turbo Stream Responses

```erb
<%# With morphing %>
<%= turbo_stream.replace dom_id(@card, :container),
    partial: "cards/container",
    method: :morph,
    locals: { card: @card.reload } %>
```

**Always use `status: :unprocessable_entity` for validation errors** to prevent Turbo from caching invalid state.

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
```

---

## Controllers & Views

### Thin Controllers

```ruby
class PostsController < ApplicationController
  before_action :set_post, only: [:show, :edit, :update, :destroy]
  before_action :require_authentication

  def create
    @post = Post.new(post_params)

    respond_to do |format|
      if @post.save
        format.html { redirect_to @post, notice: 'Post created.' }
        format.turbo_stream
      else
        format.html { render :new, status: :unprocessable_entity }
        format.turbo_stream { render status: :unprocessable_entity }
      end
    end
  end

  private

  def set_post
    @post = Post.find(params[:id])
  end

  def post_params
    params.expect(post: [:title, :body, :published])
  end
end
```

### Strong Parameters with params.expect

```ruby
# Simple attributes
def user_params
  params.expect(user: [:name, :email, :bio])
end

# With arrays
def post_params
  params.expect(post: [:title, :body, tags: []])
end

# Nested attributes (double bracket for nested arrays)
def person_params
  params.expect(
    person: [
      :name,
      addresses: [[:street, :city, :zip]],
      friends: [[:name, hobbies: []]]
    ]
  )
end
```

### Use Helpers Over ViewComponent

Keep views simple with helpers for formatting. Avoid ViewComponent complexity:

```ruby
# app/helpers/products_helper.rb
def product_price(product)
  tag.span(number_to_currency(product.price), class: price_class(product))
end

private

def price_class(product)
  product.on_sale? ? "price--sale" : "price"
end
```

### Flash with Turbo

```ruby
# For redirects (HTML response)
redirect_to @post, notice: "Post created!"

# For renders (Turbo Stream response)
format.turbo_stream do
  flash.now[:notice] = "Post created!"
  render turbo_stream: [
    turbo_stream.prepend("posts", partial: "posts/post"),
    turbo_stream.prepend("flash", partial: "shared/flash")
  ]
end
```

---

## Testing

### Pure Fixtures (No Factories)

```yaml
# test/fixtures/users.yml
david:
  id: <%= ActiveRecord::FixtureSet.identify("david", :uuid) %>
  name: David
  role: member
  identity: david
  account: acme

kevin:
  id: <%= ActiveRecord::FixtureSet.identify("kevin", :uuid) %>
  name: Kevin
  role: admin
  identity: kevin
  account: acme
```

### Test Helper Configuration

```ruby
# test/test_helper.rb
module ActiveSupport
  class TestCase
    parallelize(workers: :number_of_processors)
    fixtures :all

    include SessionTestHelper

    setup do
      Current.account = accounts(:acme)  # Default tenant context
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
  identity = identities(identity) if identity.is_a?(Symbol)
  post session_path, params: { email: identity.email, password: "secret" }
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

### Turbo Stream Test Assertions

```ruby
test "creates article with turbo stream" do
  post articles_path,
    params: { article: { title: "New", body: "Content" } },
    as: :turbo_stream

  assert_response :success
  assert_equal "text/vnd.turbo-stream.html", response.media_type
  assert_select "turbo-stream[action='prepend'][target='articles']"
end
```

### System Test Pattern

```ruby
class SmokeTest < ApplicationSystemTestCase
  test "create a card" do
    sign_in_as(users(:david))
    visit board_url(boards(:writebook))
    click_on "Add a card"
    fill_in "card_title", with: "Hello, world!"
    click_on "Create card"
    assert_selector "h3", text: "Hello, world!"
  end
end
```

**Note**: System tests run with `PARALLEL_WORKERS=1` (Capybara/Selenium doesn't parallelize well).

### CI Pipeline

```yaml
# .github/workflows/ci.yml
jobs:
  scan_ruby:
    steps:
      - run: bin/brakeman --no-pager
      - run: bin/bundler-audit

  lint:
    steps:
      - run: bin/rubocop -f github

  test:
    steps:
      - run: bin/rails db:test:prepare test

  system-test:
    steps:
      - run: bin/rails db:test:prepare test:system
```

---

## SQLite Production Configuration

### Rails 8 Optimal Defaults

```yaml
# config/database.yml
production:
  adapter: sqlite3
  database: storage/production.sqlite3
  pool: 5
  timeout: 5000
  transaction_mode: immediate  # Critical for preventing deadlocks
  # Auto-applied PRAGMAs:
  # journal_mode: WAL (concurrent reads/writes)
  # synchronous: NORMAL (balanced durability/performance)
  # mmap_size: 134217728 (128MB memory-mapped I/O)
  # foreign_keys: ON (referential integrity)
```

### Separate Databases for Different Concerns

```yaml
production:
  primary:
    adapter: sqlite3
    database: storage/production.sqlite3
    pool: 5

  cache:
    adapter: sqlite3
    database: storage/cache.sqlite3
    migrations_paths: db/cache_migrate
    pool: 5

  queue:
    adapter: sqlite3
    database: storage/queue.sqlite3
    migrations_paths: db/queue_migrate
    pool: 5
```

### Litestream for Continuous Backups

```yaml
# config/litestream.yml
dbs:
  - path: storage/production.sqlite3
    replicas:
      - type: s3
        bucket: myapp-backups
        path: production
        sync-interval: 1s
        retention: 720h  # 30 days
```

### When to Choose SQLite vs PostgreSQL

**Choose SQLite when:**
- Single-server architecture is acceptable
- Application is read-heavy (80%+ reads typical)
- Operational simplicity is valued
- Brief downtime during deploys is acceptable

**Choose PostgreSQL when:**
- Horizontal scaling across multiple app servers required
- Zero-downtime migrations mandatory
- Write-heavy workloads exceed 50k writes/second

---

## Background Jobs

### Solid Queue Configuration

```yaml
# config/queue.yml
production:
  dispatchers:
    - polling_interval: 1
      batch_size: 500

  workers:
    - queues: "*"
      threads: 3
      polling_interval: 2
    - queues: [critical, high_priority]
      threads: 5
```

### Job Best Practices

**Pass IDs, not objects:**

```ruby
# ❌ Bad
SomeJob.perform_async(user)

# ✅ Good
SomeJob.perform_async(user.id)
```

**Make jobs idempotent:**

```ruby
class ProcessPaymentJob < ApplicationJob
  def perform(payment_id)
    payment = Payment.find(payment_id)
    return if payment.processed?

    payment.process!
    payment.update!(processed: true)
  end
end
```

**Handle errors gracefully:**

```ruby
class ProcessOrderJob < ApplicationJob
  retry_on NetworkError, wait: :exponentially_longer, attempts: 5
  discard_on ActiveJob::DeserializationError
end
```

---

## Security

### Rails Provides Security by Default

- **CSRF protection**: Automatic for non-GET requests
- **XSS prevention**: Automatic HTML escaping
- **SQL injection**: Use parameterized queries

```ruby
# ❌ Vulnerable
User.where("name = '#{params[:name]}'")

# ✅ Safe
User.where(name: params[:name])
```

### Rails 8 Authentication Generator

```bash
bin/rails generate authentication
```

Creates complete authentication with `has_secure_password`, sessions, and password reset.

### Rate Limiting

```ruby
class SessionsController < ApplicationController
  rate_limit to: 10, within: 3.minutes, only: :create
end
```

### Encrypted Credentials

```bash
bin/rails credentials:edit --environment production
```

```ruby
Rails.application.credentials.dig(:aws, :access_key_id)
```

---

## Performance

### YJIT Enabled by Default

```ruby
# config/environments/production.rb
config.yjit = true if defined?(RubyVM::YJIT)
```

Provides 15-25% latency improvements.

### Puma Configuration

```ruby
# config/puma.rb
threads_count = ENV.fetch("RAILS_MAX_THREADS") { 3 }
threads threads_count, threads_count
workers ENV.fetch("WEB_CONCURRENCY") { 2 }
preload_app!
```

### Fragment Caching

```erb
<% @products.each do |product| %>
  <% cache product do %>
    <%= render product %>
  <% end %>
<% end %>
```

---

## Asset Management

### Importmaps (Preferred)

```ruby
# config/importmap.rb
pin "application", preload: true
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin_all_from "app/javascript/controllers", under: "controllers"
```

No Node.js required. Use Importmaps unless you need:
- TypeScript or JSX
- React, Vue, Svelte
- Complex npm dependencies

### Propshaft

Rails 8 default. Digests files for cache-busting without transpilation.

```erb
<%= stylesheet_link_tag "application", "data-turbo-track": "reload" %>
<%= javascript_include_tag "application", "data-turbo-track": "reload" %>
```

---

## Deployment

### Kamal for Zero-Downtime Deploys

```yaml
# config/deploy.yml
service: myapp
image: myapp/production

servers:
  web:
    hosts:
      - 192.168.0.1

volumes:
  - "storage:/rails/storage"

env:
  clear:
    RAILS_ENV: production
  secret:
    - RAILS_MASTER_KEY
```

```bash
kamal setup   # Initial setup
kamal deploy  # Deploy updates
kamal console # Rails console on production
```

### Production Readiness Checklist

**Security:**
- Force SSL enabled
- Credentials properly configured
- Brakeman scans passing
- Rate limiting configured

**Performance:**
- YJIT enabled (Ruby 3.3+)
- Database indexes optimized
- Caching enabled
- Puma properly tuned

**Backups (SQLite):**
- Litestream configured and running
- Backup restoration tested

---

## Key Takeaways

| Pattern | Approach |
|---------|----------|
| **Request Context** | `CurrentAttributes` with auto-derivation |
| **Model Isolation** | Lambda defaults on `belongs_to`, NO default_scope |
| **Job Context** | Auto-serialize/restore via GlobalID |
| **Concern Extraction** | At 40+ lines or 2+ models sharing |
| **Frontend** | Turbo Frames + Streams + Stimulus, no ViewComponent |
| **Morph Strategy** | Global `turbo_refreshes_with method: :morph` |
| **Testing** | Pure fixtures, parallel unit tests |
| **Composition** | Separate models over STI |

---

*Based on patterns from Basecamp/37signals' production applications and official Rails conventions.*
