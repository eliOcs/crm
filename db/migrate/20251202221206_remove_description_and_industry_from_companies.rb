class RemoveDescriptionAndIndustryFromCompanies < ActiveRecord::Migration[8.1]
  def change
    remove_column :companies, :description, :text
    remove_column :companies, :industry, :string
  end
end
