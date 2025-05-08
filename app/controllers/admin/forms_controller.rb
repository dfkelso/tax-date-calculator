# app/controllers/admin/forms_controller.rb
class Admin::FormsController < Admin::BaseController
  before_action :set_form, only: [:edit, :update, :destroy, :preview_dates, :fill_missing_years, :generate_ai_rules, :confirm_ai_rules, :apply_ai_rules]
  before_action :set_form_manager, only: [:index, :new, :create, :edit, :update, :destroy, :preview_dates, :fill_missing_years, :generate_ai_rules, :confirm_ai_rules, :apply_ai_rules]

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

  def fill_missing_years
    return redirect_to admin_forms_path, alert: 'Form not found.' unless @form

    # Get all calculation rules
    current_rules = @form['calculationRules'] || []

    # Find all years covered by existing rules
    covered_years = current_rules.flat_map { |rule| rule['effectiveYears'] || [] }.uniq.sort
    Rails.logger.info("Covered years: #{covered_years.inspect}")

    # Generate a range from 2019 to the current year + 1
    earliest_year = [covered_years.min || 2019, 2019].min
    latest_year = Date.today.year + 1
    all_years = (earliest_year..latest_year).to_a
    Rails.logger.info("All years to consider: #{all_years.inspect}")

    # Find missing years
    missing_years = all_years - covered_years
    Rails.logger.info("Missing years: #{missing_years.inspect}")

    if missing_years.any?
      # Generate rule suggestions ONLY for the missing years
      form_data = {
        form_number: @form['formNumber'],
        form_name: @form['formName'],
        entity_type: @form['entityType'],
        locality_type: @form['localityType'],
        locality: @form['locality'],
        missing_years: missing_years, # Pass only the missing years
        existing_rules: current_rules, # Pass the existing rules for context
        existing_years: covered_years # Pass the existing years for reference
      }

      claude_service = ClaudeService.new
      suggested_rules = claude_service.generate_missing_years(form_data)

      # Store the minimal necessary data in the Rails cache instead of session
      cache_key = "missing_years_#{@form['formNumber']}_#{Time.now.to_i}"
      Rails.cache.write(cache_key, {
        form_id: params[:id],
        missing_years: missing_years,
        form_details: {
          'formNumber' => @form['formNumber'],
          'formName' => @form['formName'],
          'entityType' => @form['entityType'],
          'localityType' => @form['localityType'],
          'locality' => @form['locality']
        },
        suggested_rules: suggested_rules
      }, expires_in: 1.week)

      # Redirect to confirmation page with just the cache key
      redirect_to confirm_missing_years_admin_form_path(params[:id], cache_key: cache_key)
    else
      flash[:notice] = "No missing years to fill. All years from #{earliest_year} to #{latest_year} are covered."
      redirect_to edit_admin_form_path(params[:id])
    end
  end

  def confirm_missing_years
    # Retrieve data from cache using the key
    cache_key = params[:cache_key]
    cached_data = Rails.cache.read(cache_key)

    unless cached_data
      flash[:alert] = "The suggested rules have expired. Please try again."
      redirect_to edit_admin_form_path(params[:id])
      return
    end

    @form_id = cached_data[:form_id]
    @missing_years = cached_data[:missing_years]
    @form_details = cached_data[:form_details]
    @suggested_rules = cached_data[:suggested_rules]

    # Keep the cache key available for the next step
    @cache_key = cache_key
  end

  def apply_missing_years
    # Get the cache key and retrieve data
    cache_key = params[:cache_key]
    cached_data = Rails.cache.read(cache_key)

    unless cached_data
      flash[:alert] = "The suggested rules have expired. Please try again."
      redirect_to edit_admin_form_path(params[:id])
      return
    end

    # Get the form
    @form = @form_manager.find_form(params[:id])

    unless @form
      flash[:alert] = "Form not found."
      redirect_to admin_forms_path
      return
    end

    # Initialize the calculation rules array if it doesn't exist
    @form['calculationRules'] ||= []

    # Parse the rules from params
    rules_to_apply = JSON.parse(params[:rules].to_json) if params[:rules].present?

    if rules_to_apply
      # Group rules by their configuration to avoid duplication
      grouped_rules = {}

      rules_to_apply.each do |year, rule|
        # Skip years that weren't selected
        next unless params["include_year_#{year}"] == "1"

        # Generate a unique key based on the rule configuration
        rule_config = rule.to_json

        grouped_rules[rule_config] ||= {
          'rule' => rule,
          'years' => []
        }

        grouped_rules[rule_config]['years'] << year.to_i
      end

      # Add each unique rule with its years to the form
      grouped_rules.each do |_, group_data|
        rule = group_data['rule']
        rule['effectiveYears'] = group_data['years'].sort
        @form['calculationRules'] << rule
      end

      # Save the updated form
      if @form_manager.update_form(params[:id], @form)
        # Clean up the cache
        Rails.cache.delete(cache_key)

        flash[:notice] = "Successfully added rules for the missing years."
      else
        flash[:alert] = "Error updating form rules."
      end
    else
      flash[:alert] = "No rules were provided."
    end

    redirect_to edit_admin_form_path(params[:id])
  end

  def generate_ai_rules
    # Show a loading message
    flash[:notice] = "Generating tax rules with AI. This may take up to 30 seconds..."

    # Extract form details
    form_data = {
      form_number: @form['formNumber'],
      form_name: @form['formName'],
      entity_type: @form['entityType'],
      locality_type: @form['localityType'],
      locality: @form['locality']
    }

    # Generate years to cover (last 7 years through next year)
    current_year = Date.today.year
    years_to_cover = ((current_year - 6)..(current_year + 1)).to_a

    # Call Claude API to get suggestions
    claude_service = ClaudeService.new
    suggested_rules = claude_service.generate_tax_rules(form_data)

    if suggested_rules
      # Store in cache with longer expiration time
      cache_key = "ai_rules_#{@form['formNumber']}_#{Time.now.to_i}"
      Rails.cache.write(cache_key, {
        form_id: params[:id],
        years: years_to_cover,
        form_details: form_data,
        suggested_rules: suggested_rules
      }, expires_in: 1.week)

      # Redirect to confirmation page with the cache key
      redirect_to confirm_ai_rules_admin_form_path(params[:id], cache_key: cache_key)
    else
      flash[:alert] = "Failed to generate rule suggestions. Please try again."
      redirect_to edit_admin_form_path(params[:id])
    end
  end

  def confirm_ai_rules
    # Retrieve data from cache using the key
    cache_key = params[:cache_key]
    @cached_data = Rails.cache.read(cache_key)

    unless @cached_data
      flash[:alert] = "The suggested rules have expired. Please try again."
      redirect_to edit_admin_form_path(params[:id])
      return
    end

    # Refresh the cache to extend its lifetime
    Rails.cache.write(cache_key, @cached_data, expires_in: 1.week)

    @form_id = @cached_data[:form_id]
    @years = @cached_data[:years]
    @form_details = @cached_data[:form_details]
    @suggested_rules = @cached_data[:suggested_rules]

    # Keep the cache key available for the next step
    @cache_key = cache_key
  end

  def apply_ai_rules
    Rails.logger.info("===== DIRECT UPDATE METHOD WITH DEDUPLICATION =====")

    # Get the form data directly from the JSON file
    json_path = Rails.root.join('config', 'forms.json')
    data = JSON.parse(File.read(json_path))

    # Get form index (0-based)
    form_index = params[:id].to_i - 1
    form = data['forms'][form_index]

    Rails.logger.info("Processing form: #{form['formNumber']}")

    # Ensure the form has a calculationRules array
    form['calculationRules'] ||= []
    Rails.logger.info("Existing rules before update: #{form['calculationRules'].inspect}")

    # Clear existing rules if requested
    if params[:replace_existing] == "1"
      form['calculationRules'] = []
    end

    # Get selected years and rules
    selected_years = params.keys.select { |k| k.start_with?('include_year_') && params[k] == '1' }
                           .map { |k| k.sub('include_year_', '').to_i }

    Rails.logger.info("Selected years: #{selected_years.inspect}")

    # Process each selected year's rule
    selected_years.each do |year|
      rule_data = params.dig('rules', year.to_s)
      next unless rule_data

      # Create the new rule structure for this year
      new_rule = {
        'dueDate' => {
          'monthsAfterYearEnd' => rule_data.dig('dueDate', 'monthsAfterYearEnd').to_i,
          'dayOfMonth' => rule_data.dig('dueDate', 'dayOfMonth').to_i
        },
        'extensionDueDate' => {
          'monthsAfterYearEnd' => rule_data.dig('extensionDueDate', 'monthsAfterYearEnd').to_i,
          'dayOfMonth' => rule_data.dig('extensionDueDate', 'dayOfMonth').to_i
        }
      }

      # Check if we have an existing rule with the same configuration
      matching_rule = nil
      form['calculationRules'].each do |existing_rule|
        next unless existing_rule['dueDate'] && existing_rule['extensionDueDate']

        # Check if the due date and extension due date match
        if existing_rule['dueDate']['monthsAfterYearEnd'] == new_rule['dueDate']['monthsAfterYearEnd'] &&
          existing_rule['dueDate']['dayOfMonth'] == new_rule['dueDate']['dayOfMonth'] &&
          existing_rule['extensionDueDate']['monthsAfterYearEnd'] == new_rule['extensionDueDate']['monthsAfterYearEnd'] &&
          existing_rule['extensionDueDate']['dayOfMonth'] == new_rule['extensionDueDate']['dayOfMonth']

          # Found a matching rule
          matching_rule = existing_rule
          break
        end
      end

      if matching_rule
        # Add this year to the existing rule's effective years
        matching_rule['effectiveYears'] ||= []
        matching_rule['effectiveYears'] << year
        matching_rule['effectiveYears'] = matching_rule['effectiveYears'].uniq.sort
        Rails.logger.info("Added year #{year} to existing rule: #{matching_rule.inspect}")
      else
        # Create a new rule for this year
        new_rule['effectiveYears'] = [year]
        form['calculationRules'] << new_rule
        Rails.logger.info("Created new rule for year #{year}: #{new_rule.inspect}")
      end
    end

    # Write the entire JSON back to file directly
    Rails.logger.info("Writing directly to JSON file")
    File.write(json_path, JSON.pretty_generate(data))

    # Verify the changes
    verify_data = JSON.parse(File.read(json_path))
    verify_form = verify_data['forms'][form_index]
    Rails.logger.info("Verification - rules count: #{verify_form['calculationRules'].length}")

    flash[:notice] = "Successfully added calculation rules with deduplication."
    redirect_to edit_admin_form_path(params[:id])
  end

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
    @form['calculationRules'] += new_rules

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
    @form_manager = JsonFormManager.new
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

    # Ensure all calculation rule values are integers, not strings
    if form_data['calculationRules']
      form_data['calculationRules'].each do |rule|
        if rule['dueDate']
          rule['dueDate']['monthsAfterYearEnd'] = rule['dueDate']['monthsAfterYearEnd'].to_i if rule['dueDate']['monthsAfterYearEnd']
          rule['dueDate']['dayOfMonth'] = rule['dueDate']['dayOfMonth'].to_i if rule['dueDate']['dayOfMonth']
        end

        if rule['extensionDueDate']
          rule['extensionDueDate']['monthsAfterYearEnd'] = rule['extensionDueDate']['monthsAfterYearEnd'].to_i if rule['extensionDueDate']['monthsAfterYearEnd']
          rule['extensionDueDate']['dayOfMonth'] = rule['extensionDueDate']['dayOfMonth'].to_i if rule['extensionDueDate']['dayOfMonth']
        end
      end
    end

    form_data
  end
end