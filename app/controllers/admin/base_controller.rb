# app/controllers/admin/base_controller.rb - REPLACE THE ENTIRE CLASS
class Admin::BaseController < ApplicationController
  layout 'admin'

  def index
    redirect_to admin_forms_path
  end

  def export_json
    send_data JsonFormManager.new.export_json,
              type: 'application/json',
              disposition: 'attachment',
              filename: "tax_forms_#{Date.today.strftime('%Y%m%d')}.json"
  end

  def import_json
    if params[:json_file].present?
      json_content = params[:json_file].read
      success = JsonFormManager.new.import_json(json_content)

      if success
        redirect_to admin_root_path, notice: 'JSON data imported successfully.'
      else
        redirect_to admin_root_path, alert: 'Failed to import JSON. Please check the file format.'
      end
    else
      redirect_to admin_root_path, alert: 'Please select a JSON file to import.'
    end
  end
end