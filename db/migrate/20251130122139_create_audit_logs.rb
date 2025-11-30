class CreateAuditLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :audit_logs do |t|
      t.references :user, null: false, foreign_key: true
      t.string :auditable_type, null: false
      t.bigint :auditable_id, null: false
      t.string :action, null: false
      t.json :changes, default: {}
      t.string :message
      t.json :metadata, default: {}
      t.timestamps
    end

    add_index :audit_logs, [ :auditable_type, :auditable_id ]
    add_index :audit_logs, [ :user_id, :created_at ]
  end
end
