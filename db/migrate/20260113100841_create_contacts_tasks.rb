class CreateContactsTasks < ActiveRecord::Migration[8.1]
  def up
    create_table :contacts_tasks, id: false do |t|
      t.belongs_to :contact, null: false, foreign_key: true
      t.belongs_to :task, null: false, foreign_key: true
    end

    add_index :contacts_tasks, [ :contact_id, :task_id ], unique: true

    # Migrate existing contact_id data to join table
    execute <<~SQL
      INSERT INTO contacts_tasks (contact_id, task_id)
      SELECT contact_id, id FROM tasks WHERE contact_id IS NOT NULL
    SQL

    remove_column :tasks, :contact_id
  end

  def down
    add_column :tasks, :contact_id, :integer

    # Migrate first contact back to contact_id
    execute <<~SQL
      UPDATE tasks
      SET contact_id = (
        SELECT contact_id FROM contacts_tasks
        WHERE contacts_tasks.task_id = tasks.id
        LIMIT 1
      )
    SQL

    add_foreign_key :tasks, :contacts

    drop_table :contacts_tasks
  end
end
