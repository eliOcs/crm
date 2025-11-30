require "test_helper"

class AuditLogTest < ActiveSupport::TestCase
  test "validates action presence" do
    audit_log = AuditLog.new(
      user: users(:one),
      auditable: companies(:one),
      action: nil
    )
    assert_not audit_log.valid?
    assert_includes audit_log.errors[:action], "can't be blank"
  end

  test "validates action inclusion" do
    audit_log = AuditLog.new(
      user: users(:one),
      auditable: companies(:one),
      action: "invalid_action"
    )
    assert_not audit_log.valid?
    assert_includes audit_log.errors[:action], "is not included in the list"
  end

  test "valid actions are accepted" do
    %w[create update destroy link unlink].each do |action|
      audit_log = AuditLog.new(
        user: users(:one),
        auditable: companies(:one),
        action: action,
        message: "test"
      )
      assert audit_log.valid?, "#{action} should be valid"
    end
  end

  test "current_version returns git short SHA" do
    version = AuditLog.current_version
    assert_match(/\A[a-f0-9]{7,}\z/, version)
  end

  test "belongs to user" do
    audit_log = audit_logs(:company_create)
    assert_equal users(:one), audit_log.user
  end

  test "belongs to auditable polymorphically" do
    audit_log = AuditLog.create!(
      user: users(:one),
      auditable: companies(:one),
      action: "update",
      message: "test"
    )
    assert_equal "Company", audit_log.auditable_type
    assert_equal companies(:one).id, audit_log.auditable_id
  end

  test "company has_many audit_logs" do
    company = companies(:one)
    AuditLog.create!(
      user: users(:one),
      auditable: company,
      action: "create",
      message: "test"
    )
    assert company.audit_logs.any?
  end

  test "contact has_many audit_logs" do
    contact = contacts(:one)
    AuditLog.create!(
      user: users(:one),
      auditable: contact,
      action: "create",
      message: "test"
    )
    assert contact.audit_logs.any?
  end

  test "field_changes are stored as JSON" do
    audit_log = AuditLog.create!(
      user: users(:one),
      auditable: companies(:one),
      action: "update",
      message: "test",
      field_changes: { "legal_name" => { "from" => "Old", "to" => "New" } }
    )
    audit_log.reload
    assert_equal({ "legal_name" => { "from" => "Old", "to" => "New" } }, audit_log.field_changes)
  end

  test "metadata is stored as JSON" do
    audit_log = AuditLog.create!(
      user: users(:one),
      auditable: companies(:one),
      action: "update",
      message: "test",
      metadata: { "version" => "abc123", "source_email" => "test.eml" }
    )
    audit_log.reload
    assert_equal "abc123", audit_log.metadata["version"]
    assert_equal "test.eml", audit_log.metadata["source_email"]
  end
end
