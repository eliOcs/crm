class RemoveDepartmentFromCompaniesContacts < ActiveRecord::Migration[8.1]
  def change
    remove_column :companies_contacts, :department, :string
  end
end
