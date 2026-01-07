class CreatePstEmailImports < ActiveRecord::Migration[8.1]
  def change
    create_table :pst_email_imports do |t|
      t.references :user, null: false, foreign_key: true
      t.string :status, null: false, default: "pending"

      t.integer :total_emails, default: 0
      t.integer :imported_emails, default: 0
      t.integer :skipped_emails, default: 0
      t.integer :failed_emails, default: 0

      t.string :original_filename
      t.bigint :file_size
      t.string :pst_file_path      # Temp path for uploaded PST
      t.string :extraction_dir     # Temp dir for extracted EMLs
      t.integer :current_index, default: 0
      t.text :error_message
      t.datetime :started_at
      t.datetime :completed_at

      t.timestamps
    end

    add_index :pst_email_imports, [ :user_id, :status ]
  end
end
