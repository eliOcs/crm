class AddGraphFieldsToEmails < ActiveRecord::Migration[8.1]
  def change
    add_column :emails, :graph_id, :string
    add_column :emails, :conversation_id, :string
    add_column :emails, :source_type, :string, default: "eml", null: false

    add_index :emails, [ :user_id, :graph_id ], unique: true, where: "graph_id IS NOT NULL"
    add_index :emails, :conversation_id
  end
end
