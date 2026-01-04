class AddInboundEmailTokenToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :inbound_email_token, :string
    add_index :users, :inbound_email_token, unique: true

    # Generate tokens for existing users
    reversible do |dir|
      dir.up do
        User.find_each do |user|
          user.update_column(:inbound_email_token, SecureRandom.alphanumeric(8).downcase)
        end
      end
    end
  end
end
