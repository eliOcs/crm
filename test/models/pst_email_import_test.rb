require "test_helper"

class PstEmailImportTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
  end

  # --- Validations ---

  test "valid with required attributes" do
    import = @user.pst_email_imports.build(
      original_filename: "backup.pst",
      file_size: 1024
    )
    assert import.valid?
  end

  test "invalid without user" do
    import = PstEmailImport.new(original_filename: "backup.pst")
    assert_not import.valid?
    assert_includes import.errors[:user], "must exist"
  end

  test "status defaults to pending" do
    import = @user.pst_email_imports.create!(original_filename: "test.pst")
    assert_equal "pending", import.status
  end

  test "invalid with unrecognized status" do
    import = @user.pst_email_imports.build(status: "invalid_status")
    assert_not import.valid?
    assert_includes import.errors[:status], "is not included in the list"
  end

  # --- Status Methods ---

  test "active? returns true for pending status" do
    import = @user.pst_email_imports.build(status: "pending")
    assert import.active?
  end

  test "active? returns true for extracting status" do
    import = @user.pst_email_imports.build(status: "extracting")
    assert import.active?
  end

  test "active? returns true for importing status" do
    import = @user.pst_email_imports.build(status: "importing")
    assert import.active?
  end

  test "active? returns true for enriching status" do
    import = @user.pst_email_imports.build(status: "enriching")
    assert import.active?
  end

  test "enriching? returns true for enriching status" do
    import = @user.pst_email_imports.build(status: "enriching")
    assert import.enriching?
  end

  test "enriching? returns false for other statuses" do
    import = @user.pst_email_imports.build(status: "importing")
    assert_not import.enriching?
  end

  test "active? returns false for completed status" do
    import = @user.pst_email_imports.build(status: "completed")
    assert_not import.active?
  end

  test "active? returns false for failed status" do
    import = @user.pst_email_imports.build(status: "failed")
    assert_not import.active?
  end

  test "active? returns false for cancelled status" do
    import = @user.pst_email_imports.build(status: "cancelled")
    assert_not import.active?
  end

  test "can_cancel? returns true for pending status" do
    import = @user.pst_email_imports.build(status: "pending")
    assert import.can_cancel?
  end

  test "can_cancel? returns true for extracting status" do
    import = @user.pst_email_imports.build(status: "extracting")
    assert import.can_cancel?
  end

  test "can_cancel? returns true for importing status" do
    import = @user.pst_email_imports.build(status: "importing")
    assert import.can_cancel?
  end

  test "can_cancel? returns true for enriching status" do
    import = @user.pst_email_imports.build(status: "enriching")
    assert import.can_cancel?
  end

  test "can_cancel? returns false for completed status" do
    import = @user.pst_email_imports.build(status: "completed")
    assert_not import.can_cancel?
  end

  test "cancelled? returns true for cancelled status" do
    import = @user.pst_email_imports.build(status: "cancelled")
    assert import.cancelled?
  end

  # --- Progress Calculation ---

  test "progress_percentage returns 0 when total_emails is 0" do
    import = @user.pst_email_imports.build(total_emails: 0)
    assert_equal 0, import.progress_percentage
  end

  test "progress_percentage calculates correct percentage" do
    import = @user.pst_email_imports.build(
      imported_emails: 15,
      skipped_emails: 5,
      failed_emails: 5,
      total_emails: 100
    )
    # processed_emails = 15 + 5 + 5 = 25
    assert_equal 25, import.progress_percentage
  end

  test "progress_percentage rounds down" do
    import = @user.pst_email_imports.build(
      imported_emails: 33,
      total_emails: 100
    )
    assert_equal 33, import.progress_percentage
  end

  test "processed_emails returns sum of imported, skipped, and failed" do
    import = @user.pst_email_imports.build(
      imported_emails: 10,
      skipped_emails: 5,
      failed_emails: 2
    )
    assert_equal 17, import.processed_emails
  end

  # --- Status Label ---

  test "status_label returns translated status" do
    import = @user.pst_email_imports.build(status: "pending")
    assert_equal I18n.t("pst_import.statuses.pending"), import.status_label
  end

  test "status_label returns translated status for extracting" do
    import = @user.pst_email_imports.build(status: "extracting")
    assert_equal I18n.t("pst_import.statuses.extracting"), import.status_label
  end

  # --- Scopes ---

  test "active scope returns only active imports" do
    active = @user.pst_email_imports.create!(status: "importing", original_filename: "a.pst")
    completed = @user.pst_email_imports.create!(status: "completed", original_filename: "b.pst")

    active_imports = @user.pst_email_imports.active
    assert_includes active_imports, active
    assert_not_includes active_imports, completed
  end

  test "recent scope returns last 5 ordered by created_at desc" do
    6.times do |i|
      @user.pst_email_imports.create!(
        original_filename: "file#{i}.pst",
        created_at: i.hours.ago
      )
    end

    recent = @user.pst_email_imports.recent
    assert_equal 5, recent.count
    assert recent.first.created_at > recent.last.created_at
  end

  # --- Cleanup Methods ---

  test "cleanup_pst_file removes file if exists" do
    temp_dir = Rails.root.join("tmp", "test_pst_cleanup")
    FileUtils.mkdir_p(temp_dir)
    pst_path = temp_dir.join("test.pst")
    File.write(pst_path, "dummy content")

    import = @user.pst_email_imports.create!(
      original_filename: "test.pst",
      pst_file_path: pst_path.to_s
    )

    assert File.exist?(pst_path)
    import.cleanup_pst_file
    assert_not File.exist?(pst_path)
  ensure
    FileUtils.rm_rf(temp_dir)
  end

  test "cleanup_pst_file handles missing file gracefully" do
    import = @user.pst_email_imports.create!(
      original_filename: "test.pst",
      pst_file_path: "/nonexistent/path.pst"
    )

    assert_nothing_raised { import.cleanup_pst_file }
  end

  test "cleanup_extraction_dir removes directory if exists" do
    temp_dir = Rails.root.join("tmp", "test_extraction_cleanup")
    FileUtils.mkdir_p(temp_dir)
    File.write(temp_dir.join("test.eml"), "dummy")

    import = @user.pst_email_imports.create!(
      original_filename: "test.pst",
      extraction_dir: temp_dir.to_s
    )

    assert Dir.exist?(temp_dir)
    import.cleanup_extraction_dir
    assert_not Dir.exist?(temp_dir)
  ensure
    FileUtils.rm_rf(temp_dir)
  end

  test "cleanup_extraction_dir handles missing directory gracefully" do
    import = @user.pst_email_imports.create!(
      original_filename: "test.pst",
      extraction_dir: "/nonexistent/dir"
    )

    assert_nothing_raised { import.cleanup_extraction_dir }
  end

  test "cleanup_temp_files removes both pst file and extraction dir" do
    temp_dir = Rails.root.join("tmp", "test_cleanup_both")
    FileUtils.mkdir_p(temp_dir)

    pst_path = temp_dir.join("test.pst")
    File.write(pst_path, "pst content")

    extraction_dir = temp_dir.join("extraction")
    FileUtils.mkdir_p(extraction_dir)
    File.write(extraction_dir.join("email.eml"), "eml content")

    import = @user.pst_email_imports.create!(
      original_filename: "test.pst",
      pst_file_path: pst_path.to_s,
      extraction_dir: extraction_dir.to_s
    )

    import.cleanup_temp_files

    assert_not File.exist?(pst_path)
    assert_not Dir.exist?(extraction_dir)
  ensure
    FileUtils.rm_rf(temp_dir)
  end

  # --- Sent PST File Methods ---

  test "cleanup_sent_pst_file removes file if exists" do
    temp_dir = Rails.root.join("tmp", "test_sent_pst_cleanup")
    FileUtils.mkdir_p(temp_dir)
    sent_pst_path = temp_dir.join("sent.pst")
    File.write(sent_pst_path, "dummy content")

    import = @user.pst_email_imports.create!(
      original_filename: "inbox.pst",
      sent_pst_file_path: sent_pst_path.to_s,
      sent_original_filename: "sent.pst"
    )

    assert File.exist?(sent_pst_path)
    import.cleanup_sent_pst_file
    assert_not File.exist?(sent_pst_path)
  ensure
    FileUtils.rm_rf(temp_dir)
  end

  test "cleanup_sent_pst_file handles missing file gracefully" do
    import = @user.pst_email_imports.create!(
      original_filename: "inbox.pst",
      sent_pst_file_path: "/nonexistent/sent.pst"
    )

    assert_nothing_raised { import.cleanup_sent_pst_file }
  end

  test "cleanup_pst_files removes both inbox and sent pst files" do
    temp_dir = Rails.root.join("tmp", "test_cleanup_both_pst")
    FileUtils.mkdir_p(temp_dir)

    inbox_path = temp_dir.join("inbox.pst")
    sent_path = temp_dir.join("sent.pst")
    File.write(inbox_path, "inbox content")
    File.write(sent_path, "sent content")

    import = @user.pst_email_imports.create!(
      original_filename: "inbox.pst",
      pst_file_path: inbox_path.to_s,
      sent_original_filename: "sent.pst",
      sent_pst_file_path: sent_path.to_s
    )

    import.cleanup_pst_files

    assert_not File.exist?(inbox_path)
    assert_not File.exist?(sent_path)
  ensure
    FileUtils.rm_rf(temp_dir)
  end

  # --- Display Filenames ---

  test "display_filenames returns only inbox filename when no sent file" do
    import = @user.pst_email_imports.build(
      original_filename: "inbox.pst"
    )

    assert_equal "inbox.pst", import.display_filenames
  end

  test "display_filenames returns both filenames when sent file present" do
    import = @user.pst_email_imports.build(
      original_filename: "inbox.pst",
      sent_original_filename: "sent.pst"
    )

    assert_equal "inbox.pst, sent.pst", import.display_filenames
  end
end
