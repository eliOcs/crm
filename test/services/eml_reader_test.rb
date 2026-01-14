require "test_helper"

class EmlReaderTest < ActiveSupport::TestCase
  test "extracts RFC 2231 encoded filenames and detects content type" do
    path = Rails.root.join("test/fixtures/files/emails/attachments_rfc2231.eml")
    email = EmlReader.new(path).read

    file_attachments = email[:attachments].reject { |a| a[:inline] }

    expected = [
      { filename: "Synerox (2).jpg", content_type: "image/jpeg" },
      { filename: "Synerox (1).jpg", content_type: "image/jpeg" },
      { filename: "solució mare (2).jpg", content_type: "image/jpeg" },
      { filename: "solució mare (1).jpg", content_type: "image/jpeg" },
      { filename: "solució filla (3).jpg", content_type: "image/jpeg" },
      { filename: "solució filla (2).jpg", content_type: "image/jpeg" },
      { filename: "solució filla (1).jpg", content_type: "image/jpeg" },
      { filename: "Aceite (3).jpg", content_type: "image/jpeg" },
      { filename: "Aceite (2).jpg", content_type: "image/jpeg" },
      { filename: "Aceite (1).jpg", content_type: "image/jpeg" }
    ]

    assert_equal expected.length, file_attachments.length

    expected.each_with_index do |exp, i|
      assert_equal exp[:filename], file_attachments[i][:filename], "Filename mismatch at index #{i}"
      assert_equal exp[:content_type], file_attachments[i][:content_type], "Content-type mismatch at index #{i}"
    end
  end

  test "handles malformed To and Cc headers without email addresses" do
    path = Rails.root.join("test/fixtures/files/emails/malformed_to_header.eml")
    email = EmlReader.new(path).read

    # Should not raise an error
    assert_not_nil email

    # From header is valid and should be extracted
    assert_equal "sender@example.com", email[:from][:email]
    assert_equal "Test Sender", email[:from][:name]

    # To header contains only names (no email addresses), should return empty array
    assert_equal [], email[:to]

    # Cc header is also malformed, should return empty array
    assert_equal [], email[:cc]

    # Other fields should still be extracted
    assert_equal "Test email with malformed To header", email[:subject]
    assert_equal "test-malformed-123@example.com", Mail.read(path).message_id
  end
end
