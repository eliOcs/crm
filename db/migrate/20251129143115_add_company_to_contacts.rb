class AddCompanyToContacts < ActiveRecord::Migration[8.1]
  def change
    add_reference :contacts, :company, null: true, foreign_key: true
  end
end
