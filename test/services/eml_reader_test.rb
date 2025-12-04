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
end
