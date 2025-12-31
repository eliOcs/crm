class CreateEmailAttachments < ActiveRecord::Migration[8.1]
  def change
    create_table :email_attachments do |t|
      t.references :email, null: false, foreign_key: true

      t.string :filename, null: false
      t.string :content_type, null: false
      t.integer :byte_size, null: false
      t.string :content_id       # CID for inline images
      t.boolean :inline, default: false, null: false
      t.string :checksum, null: false # MD5 for deduplication

      t.timestamps
    end

    add_index :email_attachments, :content_id
    add_index :email_attachments, [ :email_id, :inline ]
  end
end
