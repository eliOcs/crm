class AddFieldsToTasks < ActiveRecord::Migration[8.1]
  def change
    add_reference :tasks, :contact, foreign_key: true
    add_reference :tasks, :company, foreign_key: true
    add_column :tasks, :due_date, :date
    add_column :tasks, :source_email, :string
    add_index :tasks, :due_date
  end
end
