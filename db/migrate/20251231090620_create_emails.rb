class CreateEmails < ActiveRecord::Migration[8.1]
  def change
    create_table :emails do |t|
      t.references :user, null: false, foreign_key: true
      t.references :contact, null: true, foreign_key: true # Sender

      t.string :subject
      t.datetime :sent_at, null: false
      t.text :body_plain
      t.text :body_html

      t.json :from_address, null: false   # {email:, name:}
      t.json :to_addresses, default: []   # [{email:, name:}, ...]
      t.json :cc_addresses, default: []

      # Threading (RFC 5322)
      t.string :message_id
      t.string :in_reply_to
      t.json :references, default: []

      t.string :source_path # Original EML path for audit

      t.timestamps
    end

    add_index :emails, [ :user_id, :sent_at ]
    add_index :emails, [ :user_id, :message_id ], unique: true, where: "message_id IS NOT NULL"
    add_index :emails, :in_reply_to
  end
end
