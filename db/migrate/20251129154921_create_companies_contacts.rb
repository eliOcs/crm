class CreateCompaniesContacts < ActiveRecord::Migration[8.1]
  def up
    # Create join table
    create_table :companies_contacts, id: false do |t|
      t.references :company, null: false, foreign_key: true
      t.references :contact, null: false, foreign_key: true
    end

    add_index :companies_contacts, [ :company_id, :contact_id ], unique: true
    add_index :companies_contacts, [ :contact_id, :company_id ]

    # Migrate existing data
    execute <<-SQL
      INSERT INTO companies_contacts (company_id, contact_id)
      SELECT company_id, id FROM contacts WHERE company_id IS NOT NULL
    SQL

    # Remove old column
    remove_column :contacts, :company_id
  end

  def down
    add_reference :contacts, :company, foreign_key: true

    # Migrate data back (takes first company if multiple)
    execute <<-SQL
      UPDATE contacts
      SET company_id = (
        SELECT company_id FROM companies_contacts
        WHERE companies_contacts.contact_id = contacts.id
        LIMIT 1
      )
    SQL

    drop_table :companies_contacts
  end
end
