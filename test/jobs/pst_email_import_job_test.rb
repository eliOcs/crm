require "test_helper"
require "ostruct"

class PstEmailImportJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = users(:one)
    @temp_dir = Rails.root.join("tmp", "test_pst_import_#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(@temp_dir)
  end

  teardown do
    FileUtils.rm_rf(@temp_dir) if @temp_dir && Dir.exist?(@temp_dir)
  end

  # --- Discard Behavior ---

  test "discards job when import record not found" do
    assert_nothing_raised do
      PstEmailImportJob.perform_now(import_id: 99999)
    end
  end

  # --- Cancellation ---

  test "skips processing when import is cancelled" do
    import = @user.pst_email_imports.create!(
      status: "cancelled",
      original_filename: "test.pst"
    )

    # Should not raise or change status
    assert_no_changes -> { import.reload.status } do
      PstEmailImportJob.perform_now(import_id: import.id)
    end
  end

  test "skips batch processing when cancelled mid-import" do
    extraction_dir = @temp_dir.join("extraction")
    FileUtils.mkdir_p(extraction_dir)
    create_test_eml(extraction_dir.join("email1.eml"), "2024-01-10")
    create_test_eml(extraction_dir.join("email2.eml"), "2024-01-15")

    import = @user.pst_email_imports.create!(
      status: "importing",
      original_filename: "test.pst",
      extraction_dir: extraction_dir.to_s,
      total_emails: 2,
      current_index: 0
    )

    # Simulate cancellation during processing
    import.update!(status: "cancelled")

    # Should handle gracefully
    assert_nothing_raised do
      PstEmailImportJob.perform_now(import_id: import.id)
    end
  end

  # --- Status Transitions ---

  test "pending status transitions to extracting" do
    pst_path = @temp_dir.join("test.pst")
    File.write(pst_path, "dummy pst content")

    import = @user.pst_email_imports.create!(
      status: "pending",
      original_filename: "test.pst",
      pst_file_path: pst_path.to_s
    )

    PstEmailImportJob.perform_now(import_id: import.id)

    import.reload
    assert_equal "extracting", import.status
    assert_not_nil import.started_at
  end

  test "pending status enqueues next job for extraction" do
    pst_path = @temp_dir.join("test.pst")
    File.write(pst_path, "dummy pst content")

    import = @user.pst_email_imports.create!(
      status: "pending",
      original_filename: "test.pst",
      pst_file_path: pst_path.to_s
    )

    assert_enqueued_with(job: PstEmailImportJob) do
      PstEmailImportJob.perform_now(import_id: import.id)
    end
  end

  # --- Error Handling ---

  test "handles extraction error gracefully" do
    import = @user.pst_email_imports.create!(
      status: "extracting",
      original_filename: "test.pst",
      pst_file_path: "/nonexistent/file.pst"
    )

    PstEmailImportJob.perform_now(import_id: import.id)

    import.reload
    assert_equal "failed", import.status
    assert_not_nil import.error_message
    assert_not_nil import.completed_at
  end

  # --- Batch Processing ---

  # Note: Full batch processing tests would require mocking EmailProcessingService
  # Since we don't have Mocha/rspec-mocks, we test what we can without mocking

  test "processes emails in batch and completes when empty batch" do
    extraction_dir = @temp_dir.join("extraction")
    FileUtils.mkdir_p(extraction_dir)
    # Empty directory - should complete immediately

    import = @user.pst_email_imports.create!(
      status: "importing",
      original_filename: "test.pst",
      extraction_dir: extraction_dir.to_s,
      total_emails: 0,
      current_index: 0
    )

    PstEmailImportJob.perform_now(import_id: import.id)

    import.reload
    assert_equal "completed", import.status
    assert_not_nil import.completed_at
  end

  test "cleans up temp files on completion" do
    extraction_dir = @temp_dir.join("extraction")
    pst_path = @temp_dir.join("test.pst")
    FileUtils.mkdir_p(extraction_dir)
    File.write(pst_path, "dummy")
    # No EML files - will complete immediately

    import = @user.pst_email_imports.create!(
      status: "importing",
      original_filename: "test.pst",
      pst_file_path: pst_path.to_s,
      extraction_dir: extraction_dir.to_s,
      total_emails: 0,
      current_index: 0
    )

    PstEmailImportJob.perform_now(import_id: import.id)

    assert_not Dir.exist?(extraction_dir), "Extraction dir should be cleaned up"
  end

  test "error message is truncated to 500 characters" do
    import = @user.pst_email_imports.create!(
      status: "extracting",
      original_filename: "test.pst",
      pst_file_path: "/nonexistent/file.pst"
    )

    PstEmailImportJob.perform_now(import_id: import.id)

    import.reload
    assert import.error_message.length <= 500
  end

  private

  def create_test_eml(path, date_str)
    File.write(path, <<~EML)
      Date: #{date_str} 12:00:00 +0000
      From: sender@example.com
      To: recipient@example.com
      Subject: Test email dated #{date_str}
      Message-ID: <#{SecureRandom.uuid}@example.com>

      This is a test email body.
    EML
  end
end
