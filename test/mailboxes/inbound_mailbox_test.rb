require "test_helper"

class InboundMailboxTest < ActionMailbox::TestCase
  setup do
    @user = users(:one)
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
end
