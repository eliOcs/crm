class RemoveSourceEmailFromTasks < ActiveRecord::Migration[8.1]
  def change
    remove_column :tasks, :source_email, :string
  end
end
