class CreateCompanies < ActiveRecord::Migration[8.1]
  def change
    create_table :companies do |t|
      t.string :name
      t.string :website
      t.string :logo
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end
  end
end
