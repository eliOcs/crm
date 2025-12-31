class AddSourceEmailToAuditLogs < ActiveRecord::Migration[8.1]
  def change
    add_reference :audit_logs, :source_email, null: true, foreign_key: { to_table: :emails }

    # Migrate existing audit logs to use the new column
    reversible do |dir|
      dir.up do
        execute <<-SQL
          UPDATE audit_logs
          SET source_email_id = emails.id
          FROM emails
          WHERE audit_logs.metadata->>'source_email' = emails.source_path
            AND audit_logs.source_email_id IS NULL
        SQL
      end
    end
  end
end
