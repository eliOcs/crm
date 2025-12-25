class CreateMicrosoftCredentials < ActiveRecord::Migration[8.1]
  def change
    create_table :microsoft_credentials do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.string :microsoft_user_id, null: false
      t.string :email
      t.text :access_token, null: false
      t.text :refresh_token, null: false
      t.datetime :expires_at, null: false
      t.string :scope
      t.datetime :last_sync_at

      t.timestamps
    end

    add_index :microsoft_credentials, :microsoft_user_id, unique: true
  end
end
