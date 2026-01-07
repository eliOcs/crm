require "test_helper"

class PstExtractionServiceTest < ActiveSupport::TestCase
  setup do
    @temp_dir = Rails.root.join("tmp", "test_pst_extraction_#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(@temp_dir)
  end

  teardown do
    FileUtils.rm_rf(@temp_dir) if @temp_dir && Dir.exist?(@temp_dir)
  end

  # --- Initialization ---

  test "initializes with pst path and generates output_dir" do
    service = PstExtractionService.new("/path/to/file.pst")
    assert_not_nil service.output_dir
    assert service.output_dir.include?("pst_extract")
  end

  test "initializes with custom output_dir" do
    service = PstExtractionService.new("/path/to/file.pst", output_dir: @temp_dir)
    assert_equal @temp_dir.to_s, service.output_dir.to_s
  end

  # --- File Validation ---

  test "extract raises error for missing pst file" do
    service = PstExtractionService.new("/nonexistent/file.pst", output_dir: @temp_dir)

    error = assert_raises(PstExtractionService::ExtractionError) do
      service.extract
    end
    assert_includes error.message, "PST file not found"
  end

  # --- EML File Methods ---

  test "eml_files returns empty array when no files extracted" do
    service = PstExtractionService.new("/path/to/file.pst", output_dir: @temp_dir)
    assert_equal [], service.eml_files
  end

  test "eml_files returns eml files in output directory" do
    # Create some test EML files with date headers
    create_test_eml(@temp_dir.join("email1.eml"), "2024-01-15")
    create_test_eml(@temp_dir.join("email2.eml"), "2024-01-10")
    create_test_eml(@temp_dir.join("email3.eml"), "2024-01-20")

    service = PstExtractionService.new("/path/to/file.pst", output_dir: @temp_dir)
    eml_files = service.eml_files

    assert_equal 3, eml_files.count
    assert eml_files.all? { |f| f.to_s.end_with?(".eml") }
  end

  test "eml_files sorts by date oldest first" do
    # Create EML files with different dates
    create_test_eml(@temp_dir.join("newer.eml"), "2024-06-15")
    create_test_eml(@temp_dir.join("older.eml"), "2024-01-10")
    create_test_eml(@temp_dir.join("middle.eml"), "2024-03-20")

    service = PstExtractionService.new("/path/to/file.pst", output_dir: @temp_dir)
    eml_files = service.eml_files

    assert_equal 3, eml_files.count
    # Oldest should be first
    assert_equal "older.eml", File.basename(eml_files.first)
    assert_equal "newer.eml", File.basename(eml_files.last)
  end

  test "eml_files handles files without valid date header" do
    # Create a file without proper date header
    File.write(@temp_dir.join("no_date.eml"), "Subject: Test\n\nNo date header")
    create_test_eml(@temp_dir.join("with_date.eml"), "2024-01-10")

    service = PstExtractionService.new("/path/to/file.pst", output_dir: @temp_dir)
    eml_files = service.eml_files

    assert_equal 2, eml_files.count
    # File without date should be sorted to beginning (uses Time.at(0) as fallback)
    assert_equal "no_date.eml", File.basename(eml_files.first)
  end

  test "eml_files finds files in subdirectories" do
    # Create subdirectory structure (like readpst does for folders)
    subdir = @temp_dir.join("Inbox")
    FileUtils.mkdir_p(subdir)
    create_test_eml(subdir.join("email1.eml"), "2024-01-15")
    create_test_eml(@temp_dir.join("email2.eml"), "2024-01-10")

    service = PstExtractionService.new("/path/to/file.pst", output_dir: @temp_dir)
    eml_files = service.eml_files

    assert_equal 2, eml_files.count
  end

  # --- Stats ---

  test "stats initialized to zero" do
    service = PstExtractionService.new("/path/to/file.pst", output_dir: @temp_dir)
    assert_equal({ eml_count: 0, attachment_count: 0 }, service.stats)
  end

  private

  def create_test_eml(path, date_str)
    File.write(path, <<~EML)
      Date: #{date_str} 12:00:00 +0000
      From: sender@example.com
      To: recipient@example.com
      Subject: Test email dated #{date_str}

      This is a test email body.
    EML
  end
end
