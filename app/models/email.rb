class Email < ApplicationRecord
  belongs_to :user
  belongs_to :contact, optional: true # Sender contact

  has_many :email_attachments, dependent: :destroy
  has_many :audit_logs, as: :auditable, dependent: :destroy

  SOURCE_TYPES = %w[eml graph].freeze

  validates :sent_at, presence: true
  validates :from_address, presence: true
  validates :message_id, uniqueness: { scope: :user_id }, allow_nil: true
  validates :graph_id, uniqueness: { scope: :user_id }, allow_nil: true
  validates :source_type, inclusion: { in: SOURCE_TYPES }

  scope :ordered, -> { order(sent_at: :desc) }
  scope :from_eml, -> { where(source_type: "eml") }
  scope :from_graph, -> { where(source_type: "graph") }
  scope :inline_attachments, -> { email_attachments.where(inline: true) }
  scope :file_attachments, -> { email_attachments.where(inline: false) }

  # Find related emails in the same thread
  scope :threaded_with, ->(email) {
    return none unless email.message_id.present? || email.in_reply_to.present?

    where(message_id: email.in_reply_to)
      .or(where(in_reply_to: email.message_id))
  }

  # Link sender contact by email address if not already linked
  def find_or_link_sender_contact
    return contact if contact_id.present?
    return nil unless from_address&.dig("email").present?

    sender = user.contacts.find_by(email: from_address["email"].downcase)
    update!(contact: sender) if sender
    sender
  end

  # Display name for the sender
  def sender_display_name
    from_address&.dig("name").presence || from_address&.dig("email") || "(Unknown)"
  end

  # Check if email has non-inline attachments
  def has_file_attachments?
    email_attachments.where(inline: false).exists?
  end

  # Get inline attachments
  def inline_attachments
    email_attachments.where(inline: true)
  end

  # Get file (non-inline) attachments
  def file_attachments
    email_attachments.where(inline: false)
  end

  # Check if email has meaningful content worth analyzing with LLM
  # Returns false for empty emails, calendar notifications, etc.
  def has_meaningful_content?
    extract_text_content.length > 0
  end

  # Extract plain text content from email, stripping HTML
  # Uses the same HtmlToMarkdown converter used for LLM processing
  def extract_text_content
    text = if body_plain.present? && !body_plain.include?("Unable to decode")
      body_plain
    elsif body_html.present?
      HtmlToMarkdown.new(body_html).convert
    else
      ""
    end

    # Strip all whitespace including Unicode non-breaking spaces
    text.gsub(/\A[[:space:]]+|[[:space:]]+\z/, "")
  end

  # Extract all email addresses from headers (from, to, cc)
  def header_addresses
    addresses = []

    addresses << from_address if from_address.present?
    addresses.concat(to_addresses) if to_addresses.present?
    addresses.concat(cc_addresses) if cc_addresses.present?

    addresses.compact.uniq { |a| a["email"]&.downcase }
  end
end
