require "test_helper"

class LlmEmailExtractorTest < ActiveSupport::TestCase
  setup do
    @eml_path = Rails.root.join("test/fixtures/emails/itpsa_royal_protein_thread.eml").to_s
  end

  # This test uses VCR to record/replay actual API calls
  # Run with ANTHROPIC_API_KEY set to record new cassettes
  test "extracts contacts, companies, and locations from email thread" do
    result = VCR.use_cassette("llm_email_extractor_webmail_1") do
      LlmEmailExtractor.new(@eml_path).extract
    end

    # Should extract contacts from signatures in thread
    assert result[:contacts].length >= 3, "Should extract at least 3 contacts with signatures"

    # Check Anna Puchal (ITPSA)
    anna = result[:contacts].find { |c| c[:email] == "apuchal@itpsa.com" }
    assert_not_nil anna, "Should extract Anna Puchal"
    assert_equal "Anna Puchal", anna[:name]
    assert_match(/Manager/i, anna[:job_role])
    assert_match(/Food/i, anna[:department])
    assert_includes anna[:phone_numbers], "+34 93 452 03 30"

    # Check Ana Alcaraz (ITPSA)
    ana = result[:contacts].find { |c| c[:email] == "aalcaraz@itpsa.com" }
    assert_not_nil ana, "Should extract Ana Alcaraz"
    assert_match(/Ana Alcaraz/i, ana[:name])
    assert_match(/Technician/i, ana[:job_role])
    assert_match(/R.?D/i, ana[:department])

    # Check Irene from Royal Protein (from forwarded email)
    irene = result[:contacts].find { |c| c[:email] == "irene@royalprotein.com" }
    assert_not_nil irene, "Should extract Irene from forwarded email"
    assert_match(/Irene Taberner/i, irene[:name])
    assert_match(/R\s*&?\s*D/i, irene[:department])
    assert irene[:phone_numbers].any? { |p| p.include?("972") }, "Should have Girona phone number"

    # Should extract both companies
    assert result[:companies].length >= 2, "Should extract at least 2 companies"

    # Check ITPSA
    itpsa = result[:companies].find { |c| c[:commercial_name]&.match?(/ITPSA/i) }
    assert_not_nil itpsa, "Should extract ITPSA"
    assert_match(/Industrial.*Pecuaria/i, itpsa[:legal_name])
    assert_match(/itpsa\.com/, itpsa[:website])
    assert_match(/Barcelona/i, itpsa[:location])
    assert_equal "image002.png", itpsa[:logo_content_id]

    # Check Royal Protein / Royal Distribution
    royal = result[:companies].find { |c| c[:website]&.match?(/royalprotein/i) }
    assert_not_nil royal, "Should extract Royal Protein"
    assert_match(/ROYAL DISTRIBUTION/i, royal[:legal_name])
    assert_match(/Porqueres.*GIRONA.*SPAIN/i, royal[:location])
    assert_equal "image008.jpg", royal[:logo_content_id]

    # Should have image data for logos
    assert result[:image_data].key?("image002.png"), "Should have ITPSA logo data"
    assert result[:image_data].key?("image008.jpg"), "Should have Royal Protein logo data"
  end

  test "returns empty result for invalid path" do
    result = LlmEmailExtractor.new("/nonexistent/path.eml").extract

    assert_equal [], result[:contacts]
    assert_equal [], result[:companies]
    assert_equal({}, result[:image_data])
  end
end
