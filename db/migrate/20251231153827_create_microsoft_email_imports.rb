class CreateMicrosoftEmailImports < ActiveRecord::Migration[8.1]
  def change
    create_table :microsoft_email_imports do |t|
      t.references :user, null: false, foreign_key: true
      t.string :time_range, null: false  # "3_months", "1_year", "3_years"
      t.string :status, null: false, default: "pending"
      # Status: pending → counting → importing → enriching → completed/failed/cancelled

      t.integer :total_emails, default: 0
      t.integer :imported_emails, default: 0
      t.integer :enriched_emails, default: 0
      t.integer :skipped_emails, default: 0
      t.integer :failed_emails, default: 0

      t.string :current_folder
      t.text :next_link  # Microsoft Graph pagination token (can be long)
      t.text :error_message
      t.datetime :started_at
      t.datetime :completed_at

      t.timestamps
    end

    add_index :microsoft_email_imports, [ :user_id, :status ]
  end
end
