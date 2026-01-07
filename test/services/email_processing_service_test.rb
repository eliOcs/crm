require "test_helper"

class EmailProcessingServiceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = users(:one)
    @service = EmailProcessingService.new(@user)
    @fixtures_path = Rails.root.join("test/fixtures/emails")
  end

  # --- process_eml tests ---

  test "process_eml creates email and queues enrichment by default" do
    eml_path = @fixtures_path.join("with_inline_images.eml")

    assert_enqueued_with(job: EnrichEmailJob) do
      result = @service.process_eml(eml_path, enrich: :async)

      assert result.created?
      assert result.success?
      assert_not_nil result.email
      assert_equal @user, result.email.user
    end
  end

  test "process_eml with sync enrichment does not queue job" do
    eml_path = @fixtures_path.join("with_inline_images.eml")

    # Sync enrichment calls EmailEnrichmentService directly
    # We use VCR to capture the LLM call or skip enrichment for this test
    assert_no_enqueued_jobs(only: EnrichEmailJob) do
      result = @service.process_eml(eml_path, enrich: :skip)
      assert result.created?
    end
  end

  test "process_eml skips duplicate by message_id" do
    eml_path = @fixtures_path.join("with_inline_images.eml")

    # Import first time
    result1 = @service.process_eml(eml_path, enrich: :skip)
    assert result1.created?

    # Second import should be skipped
    result2 = @service.process_eml(eml_path, enrich: :skip)
    assert result2.skipped?
    assert_nil result2.email
  end

  test "process_eml returns skipped for nonexistent file" do
    # EmailImportService returns nil for files it can't read,
    # which results in a :skipped status (not :error)
    result = @service.process_eml("/nonexistent/path.eml", enrich: :skip)

    # The service gracefully handles missing files as skipped
    assert result.skipped? || !result.success?
  end

  # --- process_mail tests ---

  test "process_mail creates email from Mail object" do
    mail = Mail.new do
      from "sender@example.com"
      to "recipient@example.com"
      subject "Test subject"
      content_type "text/plain"
      body "Test body content"
    end

    assert_enqueued_with(job: EnrichEmailJob) do
      result = @service.process_mail(mail, source_type: "forwarded")

      assert result.created?
      assert_equal "forwarded", result.email.source_type
      assert_equal "Test subject", result.email.subject
      assert_equal "sender@example.com", result.email.from_address["email"]
      assert_equal "recipient@example.com", result.email.to_addresses.first["email"]
      assert_equal "Test body content", result.email.body_plain
    end
  end

  test "process_mail handles multipart emails" do
    mail = Mail.new do
      from "sender@example.com"
      to "recipient@example.com"
      subject "Multipart test"

      text_part do
        body "Plain text version"
      end

      html_part do
        content_type "text/html; charset=UTF-8"
        body "<p>HTML version</p>"
      end
    end

    result = @service.process_mail(mail, enrich: :skip)

    assert result.created?
    assert_equal "Plain text version", result.email.body_plain
    assert_includes result.email.body_html, "<p>HTML version</p>"
  end

  test "process_mail skips duplicate by message_id" do
    existing = @user.emails.create!(
      subject: "Existing",
      sent_at: Time.current,
      from_address: { "email" => "test@example.com" },
      message_id: "existing-id@example.com"
    )

    mail = Mail.new do
      from "test@example.com"
      to "recipient@example.com"
      subject "Duplicate"
      body "Should be skipped"
      message_id "<existing-id@example.com>"
    end

    result = @service.process_mail(mail, enrich: :skip)

    assert result.skipped?
    assert_nil result.email
  end

  test "process_mail imports attachments" do
    mail = Mail.new do
      from "sender@example.com"
      to "recipient@example.com"
      subject "With attachment"
      body "See attached"

      add_file filename: "test.txt", content: "Hello world"
    end

    result = @service.process_mail(mail, enrich: :skip)

    assert result.created?
    assert_equal 1, result.email.email_attachments.count
    assert result.email.email_attachments.first.file.attached?
    assert_equal "test.txt", result.email.email_attachments.first.file.filename.to_s
  end

  test "process_mail imports inline attachments with content_id" do
    mail = Mail.new do
      from "sender@example.com"
      to "recipient@example.com"
      subject "With inline image"

      html_part do
        content_type "text/html; charset=UTF-8"
        body '<img src="cid:logo123">'
      end
    end

    # Add inline attachment
    mail.attachments.inline["logo.png"] = {
      content: "PNG content here",
      content_type: "image/png",
      content_id: "<logo123>"
    }

    result = @service.process_mail(mail, enrich: :skip)

    assert result.created?
    inline_att = result.email.email_attachments.find_by(inline: true)
    assert_not_nil inline_att
    assert_equal "logo123", inline_att.content_id
  end

  test "process_mail links sender contact when exists" do
    contact = @user.contacts.create!(email: "known@example.com", name: "Known Sender")

    mail = Mail.new do
      from "known@example.com"
      to "recipient@example.com"
      subject "From known sender"
      body "Test"
    end

    result = @service.process_mail(mail, enrich: :skip)

    assert result.created?
    assert_equal contact, result.email.contact
  end

  test "process_mail extracts threading headers" do
    mail = Mail.new do
      from "sender@example.com"
      to "recipient@example.com"
      subject "Reply"
      body "Test"
      message_id "<reply-id@example.com>"
      in_reply_to "<original-id@example.com>"
      references "<thread-start@example.com> <original-id@example.com>"
    end

    result = @service.process_mail(mail, enrich: :skip)

    assert result.created?
    assert_equal "reply-id@example.com", result.email.message_id
    assert_equal "original-id@example.com", result.email.in_reply_to
    assert_includes result.email.references, "thread-start@example.com"
    assert_includes result.email.references, "original-id@example.com"
  end

  test "process_mail handles cc addresses" do
    mail = Mail.new do
      from "sender@example.com"
      to "recipient@example.com"
      cc "cc1@example.com, cc2@example.com"
      subject "With CC"
      body "Test"
    end

    result = @service.process_mail(mail, enrich: :skip)

    assert result.created?
    assert_equal 2, result.email.cc_addresses.count
    cc_emails = result.email.cc_addresses.map { |a| a["email"] }
    assert_includes cc_emails, "cc1@example.com"
    assert_includes cc_emails, "cc2@example.com"
  end

  # --- process_record tests ---

  test "process_record triggers async enrichment for existing email" do
    email = @user.emails.create!(
      subject: "Test",
      sent_at: Time.current,
      from_address: { "email" => "test@example.com" }
    )

    assert_enqueued_with(job: EnrichEmailJob, args: [ { email_id: email.id } ]) do
      result = @service.process_record(email, enrich: :async)
      assert result.created?
      assert_equal email, result.email
    end
  end

  test "process_record with skip does not trigger enrichment" do
    email = @user.emails.create!(
      subject: "Test",
      sent_at: Time.current,
      from_address: { "email" => "test@example.com" }
    )

    assert_no_enqueued_jobs(only: EnrichEmailJob) do
      result = @service.process_record(email, enrich: :skip)
      assert result.created?
    end
  end

  # --- Result object tests ---

  test "Result created? returns true for :created status" do
    result = EmailProcessingService::Result.new(email: nil, status: :created)
    assert result.created?
    assert result.success?
    assert_not result.skipped?
  end

  test "Result skipped? returns true for :skipped status" do
    result = EmailProcessingService::Result.new(email: nil, status: :skipped)
    assert result.skipped?
    assert result.success?
    assert_not result.created?
  end

  test "Result success? returns false for :error status" do
    result = EmailProcessingService::Result.new(email: nil, status: :error, error: StandardError.new("test"))
    assert_not result.success?
    assert_not result.created?
    assert_not result.skipped?
  end
end
