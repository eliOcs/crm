module Auditable
  extend ActiveSupport::Concern

  def log_audit(record:, action:, message:, field_changes: {}, metadata: {}, source_email: nil)
    AuditLog.create!(
      user: @user,
      auditable: record,
      action: action,
      message: message,
      field_changes: field_changes,
      metadata: metadata.merge(version: AuditLog.current_version),
      source_email: source_email
    )
  end

  def build_field_changes(record)
    record.saved_changes.except("created_at", "updated_at").transform_values do |change|
      { "from" => change[0], "to" => change[1] }
    end
  end
end
