class CreateContacts < ActiveRecord::Migration[8.1]
  def change
    create_table :contacts do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name
      t.string :email, null: false

      t.timestamps
    end

    add_index :contacts, [ :user_id, :email ], unique: true
  end
end
