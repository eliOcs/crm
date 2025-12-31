require "test_helper"

class EmailImportServiceTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @service = EmailImportService.new(@user)
    @fixtures_path = Rails.root.join("test/fixtures/emails")
  end

  test "imports email with basic fields" do
    eml_path = @fixtures_path.join("with_inline_images.eml")

    email = @service.import_from_eml(eml_path)

    assert_not_nil email
    assert_equal @user, email.user
    assert_equal "Test email with inline images", email.subject
    assert_equal "sender@example.com", email.from_address["email"]
    assert_equal "recipient@example.com", email.to_addresses.first["email"]
  end

  test "imports threading headers" do
    eml_path = @fixtures_path.join("with_inline_images.eml")

    email = @service.import_from_eml(eml_path)

    assert_equal "test123@example.com", email.message_id
    assert_equal "previous@example.com", email.in_reply_to
    assert_includes email.references, "original@example.com"
    assert_includes email.references, "previous@example.com"
  end

  test "preserves src attributes in HTML body" do
    eml_path = @fixtures_path.join("with_inline_images.eml")

    email = @service.import_from_eml(eml_path)

    assert_not_nil email.body_html
    assert_match(/src="cid:image001\.png@01ABC123"/, email.body_html)
    assert_match(/src="cid:image002\.jpg@01ABC123"/, email.body_html)
  end

  test "imports inline attachments with content_id" do
    eml_path = @fixtures_path.join("with_inline_images.eml")

    email = @service.import_from_eml(eml_path)

    inline_attachments = email.email_attachments.where(inline: true)
    assert_equal 2, inline_attachments.count

    content_ids = inline_attachments.pluck(:content_id)
    assert_includes content_ids, "image001.png@01ABC123"
    assert_includes content_ids, "image002.jpg@01ABC123"
  end

  test "attachments have files attached" do
    eml_path = @fixtures_path.join("with_inline_images.eml")

    email = @service.import_from_eml(eml_path)

    email.email_attachments.each do |att|
      assert att.file.attached?, "Attachment #{att.filename} should have file attached"
    end
  end

  test "skips duplicate emails by message_id" do
    eml_path = @fixtures_path.join("with_inline_images.eml")

    email1 = @service.import_from_eml(eml_path)
    email2 = @service.import_from_eml(eml_path)

    assert_not_nil email1
    assert_nil email2
    assert_equal 1, @service.stats[:imported]
    assert_equal 1, @service.stats[:skipped]
  end

  test "deduplicates attachments with same checksum" do
    eml_path = @fixtures_path.join("with_inline_images.eml")

    # Import twice (different message_ids to bypass dedup)
    email1 = @service.import_from_eml(eml_path)

    # Create second email manually with same attachment content
    email2 = @user.emails.create!(
      subject: "Second email",
      sent_at: Time.current,
      from_address: { "email" => "test@example.com" },
      message_id: "different-id@example.com"
    )

    # Get the first attachment's file content
    first_att = email1.email_attachments.first
    content = first_att.file.download

    # Create attachment with same content
    second_att = email2.email_attachments.new(
      content_id: "new-cid",
      inline: true
    )
    second_att.attach_with_dedup(
      io: content,
      filename: "duplicate.png",
      content_type: "image/png"
    )

    # Both attachments should point to same blob
    assert_equal first_att.checksum, second_att.checksum
    assert_equal first_att.file.blob_id, second_att.file.blob_id
  end

  test "links sender contact when exists" do
    contact = @user.contacts.create!(email: "sender@example.com", name: "Sender")
    eml_path = @fixtures_path.join("with_inline_images.eml")

    email = @service.import_from_eml(eml_path)

    assert_equal contact, email.contact
  end

  test "stores source path for audit trail" do
    eml_path = @fixtures_path.join("with_inline_images.eml")

    email = @service.import_from_eml(eml_path)

    assert_not_nil email.source_path
    assert_match(/with_inline_images\.eml/, email.source_path)
  end

  test "tracks import statistics" do
    eml_path = @fixtures_path.join("with_inline_images.eml")

    @service.import_from_eml(eml_path)

    assert_equal 1, @service.stats[:imported]
    assert_equal 0, @service.stats[:skipped]
    assert_equal 0, @service.stats[:errors]
  end
end
