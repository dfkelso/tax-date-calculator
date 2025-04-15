require "test_helper"

class JobFormsControllerTest < ActionDispatch::IntegrationTest
  test "should get new" do
    get job_forms_new_url
    assert_response :success
  end

  test "should get create" do
    get job_forms_create_url
    assert_response :success
  end

  test "should get index" do
    get job_forms_index_url
    assert_response :success
  end
end
