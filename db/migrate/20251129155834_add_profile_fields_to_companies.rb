class AddProfileFieldsToCompanies < ActiveRecord::Migration[8.1]
  def change
    add_column :companies, :description, :text
    add_column :companies, :industry, :string
    add_column :companies, :location, :string
  end
end
