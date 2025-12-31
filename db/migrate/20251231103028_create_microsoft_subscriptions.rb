class CreateMicrosoftSubscriptions < ActiveRecord::Migration[8.1]
  def change
    create_table :microsoft_subscriptions do |t|
      t.references :user, null: false, foreign_key: true
      t.string :subscription_id, null: false
      t.string :resource, null: false
      t.string :folder, null: false
      t.datetime :expires_at, null: false
      t.string :client_state

      t.timestamps
    end

    add_index :microsoft_subscriptions, :subscription_id, unique: true
    add_index :microsoft_subscriptions, [ :user_id, :folder ], unique: true
    add_index :microsoft_subscriptions, :expires_at
  end
end
