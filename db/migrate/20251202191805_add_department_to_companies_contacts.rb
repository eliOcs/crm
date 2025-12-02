class AddDepartmentToCompaniesContacts < ActiveRecord::Migration[8.1]
  def change
    add_column :companies_contacts, :department, :string
  end
end
