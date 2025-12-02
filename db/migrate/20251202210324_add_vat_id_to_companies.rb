class AddVatIdToCompanies < ActiveRecord::Migration[8.1]
  def change
    add_column :companies, :vat_id, :string
  end
end
