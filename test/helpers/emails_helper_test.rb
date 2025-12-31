require "test_helper"

class EmailsHelperTest < ActionView::TestCase
  include EmailsHelper

  setup do
    @user = users(:one)
    @email = @user.emails.create!(
      subject: "Test email",
      sent_at: Time.current,
      from_address: { "email" => "test@example.com", "name" => "Test" },
      body_html: nil,
      body_plain: nil
    )
  end

  test "render_email_html strips raw HTML comments" do
    @email.update!(body_html: <<~HTML)
      <!--
      /* Font Definitions */
      @font-face { font-family: "Cambria Math"; }
      -->
      <p>Hello World</p>
    HTML

    result = render_email_html(@email)

    assert_no_match(/Font Definitions/, result)
    assert_no_match(/Cambria Math/, result)
    assert_match(/Hello World/, result)
  end

  test "render_email_html strips escaped HTML comments from sanitized imports" do
    @email.update!(body_html: <<~HTML)
      &lt;!--
      /* Font Definitions */
      @font-face { font-family: "Aptos"; }
      --&gt;
      <p>Content here</p>
    HTML

    result = render_email_html(@email)

    assert_no_match(/Font Definitions/, result)
    assert_no_match(/Aptos/, result)
    assert_match(/Content here/, result)
  end

  test "render_email_html strips style tags" do
    @email.update!(body_html: <<~HTML)
      <style type="text/css">
        .MsoNormal { font-size: 11pt; }
      </style>
      <p class="MsoNormal">Email body</p>
    HTML

    result = render_email_html(@email)

    assert_no_match(/MsoNormal.*font-size/, result)
    assert_match(/Email body/, result)
  end

  test "render_email_html returns plain text in pre tag when no HTML" do
    @email.update!(body_html: nil, body_plain: "Plain text email")

    result = render_email_html(@email)

    assert_match(/<pre>Plain text email<\/pre>/, result)
  end

  test "render_email_html returns no body message when empty" do
    @email.update!(body_html: nil, body_plain: nil)

    result = render_email_html(@email)

    assert_match(/txt-subtle/, result)
  end

  test "render_email_html replaces CID references with attachment URLs" do
    @email.update!(body_html: '<img src="cid:image001.png">')

    attachment = @email.email_attachments.create!(
      filename: "image.png",
      content_type: "image/png",
      byte_size: 100,
      checksum: "abc123",
      content_id: "image001.png",
      inline: true
    )
    attachment.file.attach(
      io: StringIO.new("fake image data"),
      filename: "image.png",
      content_type: "image/png"
    )

    result = render_email_html(@email)

    assert_match(/src="\/emails\/#{@email.id}\/attachment\/image001.png"/, result)
    assert_no_match(/cid:/, result)
  end
end
