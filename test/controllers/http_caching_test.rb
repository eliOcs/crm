require "test_helper"

class HttpCachingTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)
  end

  # Contacts

  test "contacts index returns ETag and responds to conditional request" do
    get contacts_path
    assert_response :success
    assert response.headers["ETag"].present?, "Expected ETag header"

    etag = response.headers["ETag"]
    get contacts_path, headers: { "If-None-Match" => etag }
    assert_response :not_modified
  end

  test "contacts show returns ETag and responds to conditional request" do
    contact = contacts(:one)
    get contact_path(contact)
    assert_response :success
    assert response.headers["ETag"].present?, "Expected ETag header"

    etag = response.headers["ETag"]
    get contact_path(contact), headers: { "If-None-Match" => etag }
    assert_response :not_modified
  end

  # Companies

  test "companies index returns ETag and responds to conditional request" do
    get companies_path
    assert_response :success
    assert response.headers["ETag"].present?, "Expected ETag header"

    etag = response.headers["ETag"]
    get companies_path, headers: { "If-None-Match" => etag }
    assert_response :not_modified
  end

  test "companies show returns ETag and responds to conditional request" do
    company = companies(:one)
    get company_path(company)
    assert_response :success
    assert response.headers["ETag"].present?, "Expected ETag header"

    etag = response.headers["ETag"]
    get company_path(company), headers: { "If-None-Match" => etag }
    assert_response :not_modified
  end

  # Tasks

  test "tasks index returns ETag and responds to conditional request" do
    get tasks_path
    assert_response :success
    assert response.headers["ETag"].present?, "Expected ETag header"

    etag = response.headers["ETag"]
    get tasks_path, headers: { "If-None-Match" => etag }
    assert_response :not_modified
  end

  test "tasks show returns ETag and responds to conditional request" do
    task = tasks(:one)
    get task_path(task)
    assert_response :success
    assert response.headers["ETag"].present?, "Expected ETag header"

    etag = response.headers["ETag"]
    get task_path(task), headers: { "If-None-Match" => etag }
    assert_response :not_modified
  end

  # Settings

  test "settings edit returns ETag and responds to conditional request" do
    get edit_settings_path
    assert_response :success
    assert response.headers["ETag"].present?, "Expected ETag header"

    etag = response.headers["ETag"]
    get edit_settings_path, headers: { "If-None-Match" => etag }
    assert_response :not_modified
  end

  # Cache invalidation tests

  test "contacts show ETag changes when contact is updated" do
    contact = contacts(:one)
    get contact_path(contact)
    original_etag = response.headers["ETag"]

    contact.update!(name: "Updated Name")

    get contact_path(contact)
    new_etag = response.headers["ETag"]

    assert_not_equal original_etag, new_etag, "ETag should change when contact is updated"
  end

  test "companies show ETag changes when company is updated" do
    company = companies(:one)
    get company_path(company)
    original_etag = response.headers["ETag"]

    company.update!(legal_name: "Updated Company Name")

    get company_path(company)
    new_etag = response.headers["ETag"]

    assert_not_equal original_etag, new_etag, "ETag should change when company is updated"
  end

  test "tasks show ETag changes when task is updated" do
    task = tasks(:one)
    get task_path(task)
    original_etag = response.headers["ETag"]

    task.update!(name: "Updated Task Name")

    get task_path(task)
    new_etag = response.headers["ETag"]

    assert_not_equal original_etag, new_etag, "ETag should change when task is updated"
  end
end
