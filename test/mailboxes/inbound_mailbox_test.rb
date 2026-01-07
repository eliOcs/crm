require "test_helper"

class InboundMailboxTest < ActionMailbox::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = users(:one)
  end

  test "receives email and queues enrichment job" do
    assert_enqueued_with(job: EnrichEmailJob) do
      receive_inbound_email_from_mail(
        to: @user.inbound_email_address,
        from: "sender@example.com",
        subject: "Test email for enrichment",
        body: "This email should trigger enrichment"
      )
    end

    email = @user.emails.last
    assert_not_nil email
  end

  test "receives email and creates email record for user" do
    assert_difference -> { @user.emails.count }, 1 do
      receive_inbound_email_from_mail(
        to: @user.inbound_email_address,
        from: "sender@example.com",
        subject: "Test email",
        body: "Hello from the test!"
      )
    end

    email = @user.emails.last
    assert_equal "Test email", email.subject
    assert_equal "sender@example.com", email.from_address["email"]
    assert_equal "forwarded", email.source_type
  end

  test "ignores emails to unknown recipient" do
    assert_no_difference -> { Email.count } do
      receive_inbound_email_from_mail(
        to: "unknown.token@inbox.mercuriocrm.es",
        from: "sender@example.com",
        subject: "Test email",
        body: "This should be ignored"
      )
    end
  end

  test "skips duplicate emails by message_id" do
    # First email
    receive_inbound_email_from_mail(
      to: @user.inbound_email_address,
      from: "sender@example.com",
      subject: "Test email",
      body: "First version"
    )

    first_email = @user.emails.last
    message_id = first_email.message_id

    # Same email again (same message_id)
    assert_no_difference -> { @user.emails.count } do
      mail = Mail.new(
        to: @user.inbound_email_address,
        from: "sender@example.com",
        subject: "Test email",
        body: "Duplicate version",
        message_id: "<#{message_id}>"
      )
      receive_inbound_email_from_source(mail.to_s)
    end
  end

  test "links sender contact when matching email exists" do
    contact = @user.contacts.create!(
      email: "known@example.com",
      name: "Known Sender"
    )

    receive_inbound_email_from_mail(
      to: @user.inbound_email_address,
      from: "known@example.com",
      subject: "From known sender",
      body: "Hello!"
    )

    email = @user.emails.last
    assert_equal contact, email.contact
  end

  test "handles multipart emails with HTML and plain text" do
    mail = Mail.new do
      to "user@inbox.mercuriocrm.es"
      from "sender@example.com"
      subject "Multipart test"

      text_part do
        body "Plain text version"
      end

      html_part do
        content_type "text/html; charset=UTF-8"
        body "<p>HTML version</p>"
      end
    end
    # Override To with correct address
    mail.to = @user.inbound_email_address

    receive_inbound_email_from_source(mail.to_s)

    email = @user.emails.last
    assert_equal "Plain text version", email.body_plain
    assert_includes email.body_html, "<p>HTML version</p>"
  end

  test "discards email when inbound_email_enabled is false" do
    @user.update!(inbound_email_enabled: false)

    assert_no_difference -> { @user.emails.count } do
      receive_inbound_email_from_mail(
        to: @user.inbound_email_address,
        from: "sender@example.com",
        subject: "Should be discarded",
        body: "This email should not be saved"
      )
    end
  end

  test "receives BCC email via Delivered-To header" do
    # When user BCCs their inbound address, the To header contains the
    # original recipient, not the user's inbound address. Postfix adds
    # a Delivered-To header with the envelope recipient (the BCC address).
    mail = Mail.new do
      from "me@mycompany.com"
      to "client@example.com"  # Original recipient, not the user's inbound address
      subject "Sent email with BCC"
      body "This is an email I sent to a client"
    end
    mail["Delivered-To"] = @user.inbound_email_address

    assert_difference -> { @user.emails.count }, 1 do
      receive_inbound_email_from_source(mail.to_s)
    end

    email = @user.emails.last
    assert_equal "Sent email with BCC", email.subject
    assert_equal "me@mycompany.com", email.from_address["email"]
    assert_equal "client@example.com", email.to_addresses.first["email"]
  end

  test "receives BCC email via X-Original-To header" do
    # Some mail servers use X-Original-To instead of Delivered-To
    mail = Mail.new do
      from "me@mycompany.com"
      to "client@example.com"
      subject "Sent email with BCC (X-Original-To)"
      body "This is an email I sent to a client"
    end
    mail["X-Original-To"] = @user.inbound_email_address

    assert_difference -> { @user.emails.count }, 1 do
      receive_inbound_email_from_source(mail.to_s)
    end

    email = @user.emails.last
    assert_equal "Sent email with BCC (X-Original-To)", email.subject
  end
end
