class RemoveParentCompanyAndWebEnrichedFromCompanies < ActiveRecord::Migration[8.1]
  def change
    remove_reference :companies, :parent_company, foreign_key: { to_table: :companies }
    remove_column :companies, :web_enriched_at, :datetime
  end
end
