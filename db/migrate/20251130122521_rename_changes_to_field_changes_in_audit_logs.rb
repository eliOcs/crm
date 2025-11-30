class RenameChangesToFieldChangesInAuditLogs < ActiveRecord::Migration[8.1]
  def change
    rename_column :audit_logs, :changes, :field_changes
  end
end
