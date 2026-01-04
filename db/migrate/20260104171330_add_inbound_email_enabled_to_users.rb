class AddInboundEmailEnabledToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :inbound_email_enabled, :boolean, default: true, null: false
  end
end
