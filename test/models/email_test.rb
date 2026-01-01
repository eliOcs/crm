require "test_helper"

class EmailTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email_address: "test@example.com", password: "password123")
  end

  test "has_meaningful_content? returns false for empty body" do
    email = @user.emails.create!(
      subject: "Regular Email",
      from_address: { "email" => "test@example.com" },
      body_plain: "",
      body_html: "",
      sent_at: Time.current
    )
    assert_not email.has_meaningful_content?
  end

  test "has_meaningful_content? returns false for HTML with only whitespace" do
    email = @user.emails.create!(
      subject: "Regular Email",
      from_address: { "email" => "test@example.com" },
      body_html: "<html><body><p>&nbsp;</p></body></html>",
      sent_at: Time.current
    )
    assert_not email.has_meaningful_content?
  end

  test "has_meaningful_content? returns false for HTML with CSS but no text" do
    # Real-world calendar notification HTML with CSS in style tags
    email = @user.emails.create!(
      subject: "Regular Email",
      from_address: { "email" => "test@example.com" },
      body_html: '<html><head><style>p { color: red; } @font-face { font-family: "Test"; }</style></head><body><p>&nbsp;</p></body></html>',
      sent_at: Time.current
    )
    assert_not email.has_meaningful_content?
    assert_equal 0, email.extract_text_content.length
  end

  test "has_meaningful_content? returns true for email with actual content" do
    email = @user.emails.create!(
      subject: "Regular Email",
      from_address: { "email" => "test@example.com" },
      body_plain: "Hello, this is a regular email with meaningful content that needs to be processed.",
      sent_at: Time.current
    )
    assert email.has_meaningful_content?
  end

  test "header_addresses returns all addresses from headers" do
    email = @user.emails.create!(
      subject: "Test",
      from_address: { "email" => "sender@example.com", "name" => "Sender" },
      to_addresses: [
        { "email" => "recipient1@example.com", "name" => "Recipient 1" },
        { "email" => "recipient2@example.com" }
      ],
      cc_addresses: [
        { "email" => "cc@example.com", "name" => "CC Person" }
      ],
      sent_at: Time.current
    )

    addresses = email.header_addresses
    emails = addresses.map { |a| a["email"] }

    assert_includes emails, "sender@example.com"
    assert_includes emails, "recipient1@example.com"
    assert_includes emails, "recipient2@example.com"
    assert_includes emails, "cc@example.com"
    assert_equal 4, addresses.count
  end

  test "header_addresses deduplicates by email" do
    email = @user.emails.create!(
      subject: "Test",
      from_address: { "email" => "sender@example.com" },
      to_addresses: [ { "email" => "sender@example.com" } ],  # Same as from
      sent_at: Time.current
    )

    addresses = email.header_addresses
    assert_equal 1, addresses.count
  end
end
