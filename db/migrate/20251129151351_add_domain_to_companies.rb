class AddDomainToCompanies < ActiveRecord::Migration[8.1]
  def change
    add_column :companies, :domain, :string
    add_index :companies, [ :user_id, :domain ], unique: true
  end
end
