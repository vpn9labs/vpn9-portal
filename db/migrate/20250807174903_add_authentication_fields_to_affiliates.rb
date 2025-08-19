class AddAuthenticationFieldsToAffiliates < ActiveRecord::Migration[8.0]
  def change
    add_column :affiliates, :password_digest, :string unless column_exists?(:affiliates, :password_digest)
    add_column :affiliates, :company_name, :string unless column_exists?(:affiliates, :company_name)
    add_column :affiliates, :website, :string unless column_exists?(:affiliates, :website)
    add_column :affiliates, :promotional_methods, :text unless column_exists?(:affiliates, :promotional_methods)
    add_column :affiliates, :expected_referrals, :integer unless column_exists?(:affiliates, :expected_referrals)
    add_column :affiliates, :tax_id, :string unless column_exists?(:affiliates, :tax_id)
    add_column :affiliates, :address, :string unless column_exists?(:affiliates, :address)
    add_column :affiliates, :city, :string unless column_exists?(:affiliates, :city)
    add_column :affiliates, :state, :string unless column_exists?(:affiliates, :state)
    add_column :affiliates, :country, :string unless column_exists?(:affiliates, :country)
    add_column :affiliates, :postal_code, :string unless column_exists?(:affiliates, :postal_code)
    add_column :affiliates, :phone, :string unless column_exists?(:affiliates, :phone)
    add_column :affiliates, :terms_accepted, :boolean, default: false unless column_exists?(:affiliates, :terms_accepted)
  end
end
