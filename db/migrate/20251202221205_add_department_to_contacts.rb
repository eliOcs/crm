class AddDepartmentToContacts < ActiveRecord::Migration[8.1]
  def change
    add_column :contacts, :department, :string
  end
end
