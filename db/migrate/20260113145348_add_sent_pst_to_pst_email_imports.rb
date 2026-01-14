class AddSentPstToPstEmailImports < ActiveRecord::Migration[8.1]
  def change
    add_column :pst_email_imports, :sent_pst_file_path, :string
    add_column :pst_email_imports, :sent_original_filename, :string
    add_column :pst_email_imports, :sent_file_size, :bigint
  end
end
