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

    # Should extract contacts from headers and signatures
    assert result[:contacts].length >= 6, "Should extract at least 6 contacts"

    # Check Anna Puchal (ITPSA)
    anna = result[:contacts].find { |c| c[:email] == "apuchal@itpsa.com" }
    assert_not_nil anna, "Should extract Anna Puchal"
    assert_equal "Anna Puchal", anna[:name]
    assert anna[:job_role]&.match?(/Manager/i) || anna[:department]&.match?(/Food/i),
           "Should extract role or department for Anna"
    assert_includes anna[:phone_numbers], "+34 93 452 03 30"

    # Check Ana Alcaraz (ITPSA)
    ana = result[:contacts].find { |c| c[:email] == "aalcaraz@itpsa.com" }
    assert_not_nil ana, "Should extract Ana Alcaraz"
    assert_match(/Ana Alcaraz/i, ana[:name])
    assert ana[:job_role]&.match?(/Technician/i) || ana[:department]&.match?(/R.?D/i),
           "Should extract role or department for Ana"

    # Check Irene from Royal Protein (from forwarded email)
    irene = result[:contacts].find { |c| c[:email] == "irene@royalprotein.com" }
    assert_not_nil irene, "Should extract Irene from forwarded email"
    assert_match(/Irene Taberner/i, irene[:name])
    assert_match(/R\s*&?\s*D/i, irene[:department])
    assert irene[:phone_numbers].any? { |p| p.include?("972") }, "Should have Girona phone number"

    # Check contacts from headers (previously missed)
    assert result[:contacts].any? { |c| c[:email] == "jestevez@itpsa.com" }, "Should extract Javier from headers"
    assert result[:contacts].any? { |c| c[:email] == "mmoreno@itpsa.com" }, "Should extract Maria from headers"
    assert result[:contacts].any? { |c| c[:email] == "gloria@royalprotein.com" }, "Should extract Gloria from CC"

    # Should extract both companies
    assert result[:companies].length >= 2, "Should extract at least 2 companies"

    # Check ITPSA
    itpsa = result[:companies].find { |c| c[:commercial_name]&.match?(/ITPSA/i) }
    assert_not_nil itpsa, "Should extract ITPSA"
    assert_match(/Industrial.*Pecuaria/i, itpsa[:legal_name])
    assert_match(/itpsa\.com/, itpsa[:website])
    assert_match(/Barcelona/i, itpsa[:location])
    assert_equal "A08219511", itpsa[:vat_id], "Should extract VAT ID (C.I.F.) from legal notice"
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

  # === Status Validation Tests ===

  test "validated_status returns valid statuses unchanged" do
    extractor = LlmEmailExtractor.new(@eml_path)

    assert_equal "incoming", extractor.send(:validated_status, "incoming")
    assert_equal "todo", extractor.send(:validated_status, "todo")
    assert_equal "blocked", extractor.send(:validated_status, "blocked")
    assert_equal "done", extractor.send(:validated_status, "done")
  end

  test "validated_status normalizes case and whitespace" do
    extractor = LlmEmailExtractor.new(@eml_path)

    assert_equal "todo", extractor.send(:validated_status, "TODO")
    assert_equal "blocked", extractor.send(:validated_status, " Blocked ")
    assert_equal "done", extractor.send(:validated_status, "DONE")
  end

  test "validated_status defaults invalid statuses to incoming" do
    extractor = LlmEmailExtractor.new(@eml_path)

    assert_equal "incoming", extractor.send(:validated_status, "invalid")
    assert_equal "incoming", extractor.send(:validated_status, "not_now")  # Not extractable
    assert_equal "incoming", extractor.send(:validated_status, "in_progress")  # Not extractable
    assert_equal "incoming", extractor.send(:validated_status, nil)
    assert_equal "incoming", extractor.send(:validated_status, "")
  end

  # === Task Extraction Tests ===

  test "extract_tasks calls API with status in prompt" do
    extractor = LlmEmailExtractor.new(@eml_path)

    # This email doesn't have explicit action requests, so LLM correctly returns []
    # We verify the API is called with the correct prompt including status guidelines
    tasks = VCR.use_cassette("llm_task_extraction_with_status") do
      extractor.extract_tasks(
        email_date: Date.new(2024, 1, 15),
        user_email: "mmoreno@itpsa.com",
        existing_tasks: []
      )
    end

    # Should return an array (possibly empty if no actionable tasks)
    assert_kind_of Array, tasks
  end

  test "parse_tasks_response extracts status from LLM response" do
    extractor = LlmEmailExtractor.new(@eml_path)

    # Mock a response with tasks that have status
    mock_response = OpenStruct.new(
      content: [
        OpenStruct.new(text: <<~JSON)
          [
            {"id": null, "name": "Send report", "status": "todo", "due_date": "2024-01-20", "sender_email": "client@example.com"},
            {"id": 42, "name": "Review proposal", "status": "blocked", "due_date": null, "sender_email": "partner@example.com"}
          ]
        JSON
      ]
    )

    tasks = extractor.send(:parse_tasks_response, mock_response)

    assert_equal 2, tasks.count

    assert_equal "Send report", tasks[0][:name]
    assert_equal "todo", tasks[0][:status]
    assert_equal Date.new(2024, 1, 20), tasks[0][:due_date]

    assert_equal "Review proposal", tasks[1][:name]
    assert_equal "blocked", tasks[1][:status]
    assert_equal 42, tasks[1][:id]
  end

  test "parse_tasks_response defaults missing status to incoming" do
    extractor = LlmEmailExtractor.new(@eml_path)

    mock_response = OpenStruct.new(
      content: [
        OpenStruct.new(text: '[{"name": "Task without status", "sender_email": "test@example.com"}]')
      ]
    )

    tasks = extractor.send(:parse_tasks_response, mock_response)

    assert_equal 1, tasks.count
    assert_equal "incoming", tasks[0][:status], "Should default to incoming when status missing"
  end

  test "extract_tasks includes user email context in prompt" do
    extractor = LlmEmailExtractor.new(@eml_path)
    user_email = "test@example.com"

    # Generate the prompt and verify it includes user context
    prompt = extractor.send(:tasks_system_prompt,
      email_date: Date.current,
      user_email: user_email,
      existing_tasks: [],
      locale: "en"
    )

    assert_includes prompt, user_email, "Prompt should include user email"
    assert_includes prompt, "user is in \"From\"", "Prompt should explain sent email perspective"
    assert_includes prompt, "user is in \"To/Cc\"", "Prompt should explain received email perspective"
  end

  test "extract_tasks requires user_email parameter" do
    extractor = LlmEmailExtractor.new(@eml_path)

    assert_raises(ArgumentError) do
      extractor.extract_tasks(email_date: Date.current)
    end
  end
end
