class EmailAttachment < ApplicationRecord
  belongs_to :email
  has_one_attached :file

  validates :filename, presence: true
  validates :content_type, presence: true
  validates :byte_size, presence: true
  validates :checksum, presence: true

  scope :inline, -> { where(inline: true) }
  scope :files, -> { where(inline: false) }

  # Attach file with per-user deduplication
  # If a blob with the same checksum already exists for this user, reuse it
  def attach_with_dedup(io:, filename:, content_type:)
    content = io.respond_to?(:read) ? io.read : io

    self.checksum = Digest::MD5.base64digest(content)
    self.byte_size = content.bytesize
    self.filename = filename
    self.content_type = content_type

    # Look for existing blob with same checksum for this user
    existing_blob = find_existing_blob_for_user

    if existing_blob
      # Reuse existing blob - create new attachment pointing to same blob
      file.attach(existing_blob)
    else
      # Create new blob
      file.attach(
        io: StringIO.new(content),
        filename: filename,
        content_type: content_type
      )
    end

    save!
  end

  private

  def find_existing_blob_for_user
    user_id = email.user_id

    # Find any attachment for this user's emails with matching checksum
    existing = EmailAttachment
      .joins(:email)
      .where(emails: { user_id: user_id })
      .where(checksum: checksum)
      .where.not(id: id)
      .joins(:file_attachment)
      .first

    existing&.file&.blob
  end
end
