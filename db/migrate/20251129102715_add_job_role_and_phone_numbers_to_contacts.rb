class AddJobRoleAndPhoneNumbersToContacts < ActiveRecord::Migration[8.1]
  def change
    add_column :contacts, :job_role, :string
    add_column :contacts, :phone_numbers, :json, default: []
  end
end
