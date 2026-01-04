require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "downcases and strips email_address" do
    user = User.new(email_address: " DOWNCASED@EXAMPLE.COM ")
    assert_equal("downcased@example.com", user.email_address)
  end

  test "generates inbound_email_token on create" do
    user = User.create!(
      email_address: "new@example.com",
      password: "password123"
    )
    assert user.inbound_email_token.present?
    assert_equal 8, user.inbound_email_token.length
  end

  test "inbound_email_address returns correct format" do
    user = users(:one)
    expected = "one.#{user.inbound_email_token}@inbox.mercuriocrm.es"
    assert_equal expected, user.inbound_email_address
  end

  test "find_by_inbound_email returns user by token" do
    user = users(:one)
    recipient = "whatever.#{user.inbound_email_token}@inbox.mercuriocrm.es"
    assert_equal user, User.find_by_inbound_email(recipient)
  end

  test "find_by_inbound_email returns nil for wrong domain" do
    user = users(:one)
    recipient = "whatever.#{user.inbound_email_token}@wrong.domain.com"
    assert_nil User.find_by_inbound_email(recipient)
  end

  test "find_by_inbound_email returns nil for unknown token" do
    recipient = "whatever.unknowntoken@inbox.mercuriocrm.es"
    assert_nil User.find_by_inbound_email(recipient)
  end
end
