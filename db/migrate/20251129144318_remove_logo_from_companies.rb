class RemoveLogoFromCompanies < ActiveRecord::Migration[8.1]
  def change
    remove_column :companies, :logo, :string
  end
end
