class AddWebEnrichedAtToCompanies < ActiveRecord::Migration[8.1]
  def change
    add_column :companies, :web_enriched_at, :datetime
  end
end
