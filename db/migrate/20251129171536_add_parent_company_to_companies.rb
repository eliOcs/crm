class AddParentCompanyToCompanies < ActiveRecord::Migration[8.1]
  def change
    add_reference :companies, :parent_company, foreign_key: { to_table: :companies }, null: true
  end
end
