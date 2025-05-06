# app/controllers/admin/forms_controller.rb
class Admin::FormsController < Admin::BaseController
  before_action :set_form_manager
  before_action :set_form, only: [:edit, :update, :destroy, :preview_dates]

  def index
    @forms = @form_manager.all_forms
    @preview_year = params[:preview_year] || 2025

    respond_to do |format|
      format.html
      format.json do
        # Transform the forms data for the grid
        forms_with_dates = @forms.map.with_index do |form, idx|
          form_with_dates = form.dup
          form_with_dates['id'] = idx + 1

          # Calculate dates if preview_year is set
          if params[:preview_year].present?
            calculator = DueDateCalculator.new
            preview_dates = calculator.calculate_dates(
              form['formNumber'],
              form['entityType'],
              form['localityType'],
              form['locality'],
              Date.new(@preview_year.to_i, 1, 1),
              Date.new(@preview_year.to_i, 12, 31)
            )

            if preview_dates
              form_with_dates['dueDate'] = preview_dates[:due_date]
              form_with_dates['extensionDueDate'] = preview_dates[:extension_due_date]
              form_with_dates['approximated'] = preview_dates[:approximated]
            end
          end

          form_with_dates
        end

        render json: forms_with_dates
      end
    end
  end

  def new
    @form = {}
    @available_entity_types = ["individual", "corporation", "partnership", "scorp", "smllc"]
    @available_locality_types = ["federal", "state", "city"]
    @parent_forms = @form_manager.all_forms
  end

  def create
    form_data = prepare_form_params

    @form_manager.add_form(form_data)
    redirect_to admin_forms_path, notice: 'Form was successfully created.'
  end

  def edit
    @available_entity_types = ["individual", "corporation", "partnership", "scorp", "smllc"]
    @available_locality_types = ["federal", "state", "city"]
    @parent_forms = @form_manager.all_forms
  end

  def update
    form_data = prepare_form_params

    if @form_manager.update_form(params[:id], form_data)
      redirect_to edit_admin_form_path(params[:id]), notice: 'Form was successfully updated.'
    else
      @available_entity_types = ["individual", "corporation", "partnership", "scorp", "smllc"]
      @available_locality_types = ["federal", "state", "city"]
      @parent_forms = @form_manager.all_forms
      flash.now[:alert] = 'Error updating form.'
      render :edit
    end
  end

  def destroy
    @form_manager.delete_form(params[:id])
    redirect_to admin_forms_path, notice: 'Form was successfully deleted.'
  end

  def preview_dates
    if params[:year].present?
      year = params[:year].to_i
      @preview_year = year

      # Create sample dates for preview
      start_date = Date.new(year, 1, 1)
      end_date = Date.new(year, 12, 31)

      calculator = DueDateCalculator.new
      @preview_dates = calculator.calculate_dates(
        @form['formNumber'],
        @form['entityType'],
        @form['localityType'],
        @form['locality'],
        start_date,
        end_date
      )
    end
  end

  def export_json
    send_data @form_manager.export_json,
              type: 'application/json',
              disposition: 'attachment',
              filename: "tax_forms_#{Date.today.strftime('%Y%m%d')}.json"
  end

  # Generate calculation rules for a new or existing form
  def generate_calculation_rules
    form_data = {
      form_number: params[:form_number],
      form_name: params[:form_name],
      entity_type: params[:entity_type],
      locality_type: params[:locality_type],
      locality: params[:locality]
    }

    claude_service = ClaudeService.new
    calculation_rules = claude_service.generate_calculation_rules(form_data)

    if calculation_rules
      render json: calculation_rules
    else
      render json: { error: "Failed to generate calculation rules" }, status: :unprocessable_entity
    end
  end

  # Fill in missing years for an existing form
  def fill_missing_years
    @form = nil
    if params[:id] && params[:id] != 'edit'
      @form = @form_manager.find_form(params[:id])
    end

    unless @form
      render json: { error: "Form not found. Please make sure you're viewing a valid form." }, status: :not_found
      return
    end

    # Extract info needed for Claude
    form_data = {
      form_number: @form['formNumber'],
      form_name: @form['formName'],
      entity_type: @form['entityType'],
      locality_type: @form['localityType'],
      locality: @form['locality']
    }

    # Extract existing years from calculation rules
    existing_years = []
    if @form['calculationRules']
      @form['calculationRules'].each do |rule|
        existing_years += rule['effectiveYears'] if rule['effectiveYears']
      end
    end

    # Calculate missing years (last 7 years)
    current_year = Date.today.year
    all_years = (current_year - 6..current_year).to_a
    missing_years = all_years - existing_years

    if missing_years.empty?
      render json: { error: "This form already has calculation rules for the past 7 years" }
      return
    end

    # Add missing years info to the form data
    form_data[:missing_years] = missing_years
    form_data[:existing_rules] = @form['calculationRules']

    # Call Claude API to fill in missing years
    claude_service = ClaudeService.new
    new_rules = claude_service.generate_missing_years(form_data)

    if new_rules
      render json: { rules: new_rules, existing_years: existing_years }
    else
      render json: { error: "Failed to generate calculation rules for missing years" }, status: :unprocessable_entity
    end
  end

  # Update calculation rules for an existing form
  def update_calculation_rules
    @form = @form_manager.find_form(params[:id])

    unless @form
      render json: { success: false, error: 'Form not found' }, status: :not_found
      return
    end

    # Get the new rules from the request
    new_rules = params[:calculation_rules]
    existing_years = params[:existing_years] || []

    # Initialize calculation rules array if it doesn't exist
    @form['calculationRules'] ||= []

    # If we're filling missing years, we need to merge with existing rules
    if existing_years.present?
      # Keep rules for years that aren't in the new rules
      @form['calculationRules'] = @form['calculationRules'].select do |rule|
        rule['effectiveYears'] && (rule['effectiveYears'] - existing_years.map(&:to_i)).present?
      end
    else
      # If not filling missing years, replace all rules
      @form['calculationRules'] = []
    end

    # Add the new rules
    @form['calculationRules'] += new_rules.map { |r| JSON.parse(r.to_json) }

    # Update the form
    if @form_manager.update_form(params[:id], @form)
      render json: { success: true }
    else
      render json: { success: false, error: 'Failed to update form' }, status: :unprocessable_entity
    end
  end

  private

  def set_form_manager
    @form_manager = JsonFormManager.new
  end

  def set_form
    @form = @form_manager.find_form(params[:id])

    redirect_to admin_forms_path, alert: 'Form not found.' unless @form
  end

  def prepare_form_params
    is_parent = params[:is_parent] == "1"

    form_data = {
      'formNumber' => params[:form_number],
      'formName' => params[:form_name],
      'localityType' => params[:locality_type],
      'locality' => params[:locality],
      'entityType' => params[:entity_type],
      'parentFormNumbers' => is_parent ? [params[:form_number]] : [params[:parent_form_number]],
      'owner' => params[:owner] || 'MPM',
      'calculationBase' => params[:calculation_base] || 'end'
    }

    # Copy existing calculation rules if updating
    if params[:id].present? && @form && @form['calculationRules']
      form_data['calculationRules'] = @form['calculationRules']
    else
      form_data['calculationRules'] = []
    end

    # Add extension data if present
    if params[:extension_form_number].present?
      form_data['extension'] = {
        'formNumber' => params[:extension_form_number],
        'formName' => params[:extension_form_name],
        'piggybackFed' => params[:piggyback_fed] == "1"
      }
    end

    # Handle calculation rules from AI assistant if present
    if params[:calculation_rules].present?
      rules_array = []
      params[:calculation_rules].each do |_, rule_json|
        begin
          rule = JSON.parse(rule_json)
          rules_array << rule
        rescue JSON::ParserError => e
          Rails.logger.error("Failed to parse rule JSON: #{e.message}")
        end
      end
      form_data['calculationRules'] = rules_array unless rules_array.empty?
    end

    form_data
  end
end