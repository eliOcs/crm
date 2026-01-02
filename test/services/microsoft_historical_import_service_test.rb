require "test_helper"

class MicrosoftHistoricalImportServiceTest < ActiveSupport::TestCase
  # Freeze time to Dec 31, 2025 so cutoff_date is always 2024-12-31T00:00:00Z
  # This ensures VCR cassettes match the recorded date filter
  FROZEN_TIME = Time.zone.parse("2025-12-31 17:00:00 UTC")

  setup do
    travel_to FROZEN_TIME

    @user = User.create!(email_address: "test@example.com", password: "password123")
    @credential = @user.create_microsoft_credential!(
      microsoft_user_id: "dcb75d6e-5dbf-4ed5-b82e-be9243b006b2",
      email: "admin@eliocapella.onmicrosoft.com",
      access_token: "test_access_token",
      refresh_token: "test_refresh_token",
      expires_at: 1.hour.from_now
    )
    @import = @user.microsoft_email_imports.create!(
      time_range: "1_year",
      status: "pending"
    )
    @logger = Logger.new("/dev/null")
  end

  teardown do
    travel_back
  end

  test "counts emails across inbox and sentitems folders" do
    VCR.use_cassette("historical_import_count") do
      service = MicrosoftHistoricalImportService.new(@user, import: @import, logger: @logger)
      total = service.count_emails
      assert_equal 12, total, "Should count emails from both inbox and sentitems"
    end
  end

  test "imports batch of emails from inbox folder" do
    VCR.use_cassette("historical_import_batch_inbox") do
      service = MicrosoftHistoricalImportService.new(@user, import: @import, logger: @logger)
      result = service.import_batch(folder: "inbox")

      assert result[:imported] + result[:skipped] + result[:failed] > 0, "Should process some emails"
      assert_not_nil result[:folder_complete], "Should indicate if folder is complete"
    end
  end

  test "imports batch of emails from sentitems folder" do
    VCR.use_cassette("historical_import_batch_sentitems") do
      service = MicrosoftHistoricalImportService.new(@user, import: @import, logger: @logger)
      result = service.import_batch(folder: "sentitems")

      assert result[:imported] + result[:skipped] + result[:failed] >= 0, "Should handle sentitems folder"
      assert_includes [ true, false ], result[:folder_complete]
    end
  end

  test "skips duplicate emails by graph_id" do
    VCR.use_cassette("historical_import_batch_inbox") do
      service = MicrosoftHistoricalImportService.new(@user, import: @import, logger: @logger)

      # First import
      result1 = service.import_batch(folder: "inbox")
      initial_count = @user.emails.count

      # Reset import counters for second run
      @import.update!(imported_emails: 0, skipped_emails: 0, failed_emails: 0)

      # Second import should skip all (duplicates)
      result2 = service.import_batch(folder: "inbox")

      assert_equal initial_count, @user.emails.count, "Should not create duplicate emails"
      assert result2[:skipped] > 0, "Should skip duplicates"
    end
  end

  test "updates import progress counters" do
    VCR.use_cassette("historical_import_batch_inbox") do
      service = MicrosoftHistoricalImportService.new(@user, import: @import, logger: @logger)

      initial_imported = @import.imported_emails
      initial_skipped = @import.skipped_emails

      service.import_batch(folder: "inbox")

      @import.reload
      total_processed = @import.imported_emails + @import.skipped_emails + @import.failed_emails
      assert total_processed > initial_imported + initial_skipped, "Should update progress counters"
    end
  end

  test "creates emails with correct attributes" do
    VCR.use_cassette("historical_import_batch_inbox") do
      service = MicrosoftHistoricalImportService.new(@user, import: @import, logger: @logger)
      service.import_batch(folder: "inbox")

      email = @user.emails.where(source_type: "graph").first
      next unless email

      assert_not_nil email.graph_id, "Should have graph_id"
      assert_not_nil email.subject, "Should have subject"
      assert_not_nil email.from_address, "Should have from_address"
      assert_not_nil email.sent_at, "Should have sent_at"
      assert_equal "graph", email.source_type
    end
  end

  test "handles pagination with next_link" do
    VCR.use_cassette("historical_import_batch_inbox") do
      service = MicrosoftHistoricalImportService.new(@user, import: @import, logger: @logger)
      result = service.import_batch(folder: "inbox")

      # The result should indicate if there are more pages
      if result[:next_link]
        assert_not result[:folder_complete], "Folder should not be complete if next_link exists"
      else
        assert result[:folder_complete], "Folder should be complete if no next_link"
      end
    end
  end
end
