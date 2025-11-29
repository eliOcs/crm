class RenameNameToLegalNameAndAddCommercialName < ActiveRecord::Migration[8.1]
  def change
    rename_column :companies, :name, :legal_name
    add_column :companies, :commercial_name, :string
  end
end
