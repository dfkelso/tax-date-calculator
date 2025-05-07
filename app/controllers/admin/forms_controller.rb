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

    # Generate a range from 2020 to the current year + 1
    earliest_year = [covered_years.min || 2020, 2020].min
    latest_year = Date.today.year + 1
    all_years = (earliest_year..latest_year).to_a

    # Find missing years
    missing_years = all_years - covered_years

    if missing_years.any?
      # Generate rule suggestions for the missing years
      form_data = {
        form_number: @form['formNumber'],
        form_name: @form['formName'],
        entity_type: @form['entityType'],
        locality_type: @form['localityType'],
        locality: @form['locality']
      }

      claude_service = ClaudeService.new
      suggested_rules = claude_service.generate_missing_years(form_data, missing_years, current_rules)

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
      }, expires_in: 1.hour)

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
    # Debug the Anthropic gem
    puts "Anthropic gem version: #{Anthropic::VERSION}"
    puts "Anthropic::Client initialization parameters: #{Anthropic::Client.instance_method(:initialize).parameters.inspect}"
    puts "Available methods: #{Anthropic::Client.instance_methods(false).inspect}"
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

    # Call Claude API to get suggestions using direct HTTP
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
      }, expires_in: 2.hours) # Increase cache time to 2 hours

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
    Rails.cache.write(cache_key, @cached_data, expires_in: 2.hours)

    @form_id = @cached_data[:form_id]
    @years = @cached_data[:years]
    @form_details = @cached_data[:form_details]
    @suggested_rules = @cached_data[:suggested_rules]

    # Keep the cache key available for the next step
    @cache_key = cache_key
  end
  # In app/controllers/admin/forms_controller.rb
  def apply_ai_rules
    Rails.logger.info("=== STARTING apply_ai_rules for form ID: #{params[:id]} ===")

    # Get the form
    @form = @form_manager.find_form(params[:id])
    Rails.logger.info("Found form: #{!@form.nil?}")

    unless @form
      flash[:alert] = "Form not found."
      redirect_to admin_forms_path
      return
    end

    # Print original form data
    Rails.logger.info("Original form: #{@form.inspect}")

    # Clear existing rules if requested
    if params[:replace_existing] == "1"
      Rails.logger.info("Replacing existing rules")
      @form['calculationRules'] = []
    else
      Rails.logger.info("Adding to existing rules")
      @form['calculationRules'] ||= []
    end

    # Find all selected years
    selected_years = []
    params.each_key do |key|
      if key.start_with?('include_year_') && params[key] == '1'
        year = key.sub('include_year_', '').to_i
        selected_years << year
      end
    end
    Rails.logger.info("Selected years: #{selected_years.inspect}")

    # Create rules directly
    new_rules = []

    # Group by common configuration
    rule_groups = {}

    selected_years.each do |year|
      next unless params.dig('rules', year.to_s)

      # Extract rule data
      rule_data = params.dig('rules', year.to_s)

      # Convert to proper format with integers
      processed_rule = {
        'dueDate' => {
          'monthsAfterYearEnd' => rule_data['dueDate']['monthsAfterYearEnd'].to_i,
          'dayOfMonth' => rule_data['dueDate']['dayOfMonth'].to_i
        },
        'extensionDueDate' => {
          'monthsAfterYearEnd' => rule_data['extensionDueDate']['monthsAfterYearEnd'].to_i,
          'dayOfMonth' => rule_data['extensionDueDate']['dayOfMonth'].to_i
        }
      }

      # Create a key for grouping rules
      key = processed_rule.to_json

      # Add to group
      rule_groups[key] ||= []
      rule_groups[key] << year

      Rails.logger.info("Processed rule for year #{year}: #{processed_rule.inspect}")
    end

    # Create the final rules
    rule_groups.each do |key, years|
      rule = JSON.parse(key)
      rule['effectiveYears'] = years.sort

      new_rules << rule
      @form['calculationRules'] << rule

      Rails.logger.info("Added rule: #{rule.inspect}")
    end

    Rails.logger.info("Form after adding rules: #{@form.inspect}")

    # Save the form
    result = @form_manager.update_form(params[:id], @form)
    Rails.logger.info("Save result: #{result}")

    if result
      flash[:notice] = "Successfully added #{new_rules.size} calculation rules."
    else
      flash[:alert] = "Error saving calculation rules."
    end

    # Final verification
    updated_form = @form_manager.find_form(params[:id])
    if updated_form
      Rails.logger.info("Form after reload: #{updated_form.inspect}")
    else
      Rails.logger.error("Could not reload form after update!")
    end

    redirect_to edit_admin_form_path(params[:id])
  end
  def fill_missing_years
    return redirect_to admin_forms_path, alert: 'Form not found.' unless @form

    # Get all calculation rules
    current_rules = @form['calculationRules'] || []

    # Find all years covered by existing rules
    covered_years = current_rules.flat_map { |rule| rule['effectiveYears'] || [] }.uniq.sort

    # Generate a range from 2020 to the current year + 1
    earliest_year = [covered_years.min || 2020, 2020].min
    latest_year = Date.today.year + 1
    all_years = (earliest_year..latest_year).to_a

    # Find missing years
    missing_years = all_years - covered_years

    if missing_years.any?
      # Generate rule suggestions for the missing years
      form_data = {
        form_number: @form['formNumber'],
        form_name: @form['formName'],
        entity_type: @form['entityType'],
        locality_type: @form['localityType'],
        locality: @form['locality']
      }

      claude_service = ClaudeService.new
      suggested_rules = claude_service.generate_missing_years(form_data, missing_years, current_rules)

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
      }, expires_in: 1.hour)

      # Redirect to confirmation page with just the cache key
      redirect_to confirm_missing_years_admin_form_path(params[:id], cache_key: cache_key)
    else
      flash[:notice] = "No missing years to fill. All years from #{earliest_year} to #{latest_year} are covered."
      redirect_to edit_admin_form_path(params[:id])
    end
  end


  def apply_ai_rules
    Rails.logger.info("===== APPLYING AI RULES =====")

    # Get data from cache
    cache_key = params[:cache_key]
    cached_data = Rails.cache.read(cache_key)
    Rails.logger.info("Cache key: #{cache_key}")
    Rails.logger.info("Cached data exists: #{!cached_data.nil?}")

    # Get the form
    @form = @form_manager.find_form(params[:id])
    Rails.logger.info("Form found: #{!@form.nil?}")

    unless @form
      flash[:alert] = "Form not found."
      redirect_to admin_forms_path
      return
    end

    # Check for existing rules
    rules_before = @form['calculationRules'] || []
    Rails.logger.info("Rules before update: #{rules_before.inspect}")

    # Clear existing rules if requested
    if params[:replace_existing] == "1"
      Rails.logger.info("Replacing existing rules")
      @form['calculationRules'] = []
    else
      Rails.logger.info("Adding to existing rules")
      @form['calculationRules'] ||= []
    end

    # Collect the years that were selected
    selected_years = params.keys
                           .select { |k| k.match(/^include_year_(\d+)$/) && params[k] == "1" }
                           .map { |k| k.match(/^include_year_(\d+)$/)[1].to_i }

    Rails.logger.info("Selected years: #{selected_years.inspect}")

    # Group the rules by their properties
    grouped_rules = {}

    selected_years.each do |year|
      # Skip if no rule data for this year
      next unless params.dig("rules", year.to_s)

      rule_data = params.dig("rules", year.to_s)
      Rails.logger.info("Rule data for year #{year}: #{rule_data.inspect}")

      # Create a simplified version of the rule for grouping
      rule_key = {
        dueDate: rule_data["dueDate"],
        extensionDueDate: rule_data["extensionDueDate"]
      }.to_json

      # Group years with the same rule
      grouped_rules[rule_key] ||= {
        years: [],
        rule: rule_data
      }

      grouped_rules[rule_key][:years] << year
    end

    Rails.logger.info("Grouped rules: #{grouped_rules.inspect}")

    # Create and add the rules
    new_rules = []
    grouped_rules.each do |_, group|
      rule = {
        "effectiveYears" => group[:years],
        "dueDate" => group[:rule]["dueDate"],
        "extensionDueDate" => group[:rule]["extensionDueDate"]
      }

      # Convert string keys to integers where needed
      ["dueDate", "extensionDueDate"].each do |date_type|
        next unless rule[date_type]

        ["monthsAfterYearEnd", "dayOfMonth"].each do |key|
          rule[date_type][key] = rule[date_type][key].to_i if rule[date_type][key]
        end

        if rule[date_type]["fiscalYearExceptions"]
          rule[date_type]["fiscalYearExceptions"].each do |month, exception|
            ["monthsAfterYearEnd", "dayOfMonth"].each do |key|
              exception[key] = exception[key].to_i if exception[key]
            end
          end
        end
      end

      # Add the rule to the form
      @form['calculationRules'] << rule
      new_rules << rule
    end

    Rails.logger.info("New rules to add: #{new_rules.inspect}")
    Rails.logger.info("Rules after update (before save): #{@form['calculationRules'].inspect}")

    # Save the updated form
    result = @form_manager.update_form(params[:id], @form)
    Rails.logger.info("Update result: #{result}")

    if result
      flash[:notice] = "Successfully added AI-generated rules to the form."
    else
      flash[:alert] = "Error updating form rules."
    end

    # Check if the form was actually updated
    updated_form = @form_manager.find_form(params[:id])
    if updated_form
      Rails.logger.info("Form after refresh - has calculationRules: #{updated_form.key?('calculationRules')}")
      if updated_form['calculationRules']
        Rails.logger.info("Rules count after refresh: #{updated_form['calculationRules'].length}")
        Rails.logger.info("Rules after refresh: #{updated_form['calculationRules'].inspect}")
      end
    end

    redirect_to edit_admin_form_path(params[:id])
  end
  def apply_ai_rules
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

    # Clear existing rules if requested
    @form['calculationRules'] = [] if params[:replace_existing] == "1"
    @form['calculationRules'] ||= []

    # Parse the rules from params
    rules_to_apply = {}

    params.each do |key, value|
      if key.start_with?('rules')
        # Extract the year and rule parts from the parameter key
        # Format: rules[2023][dueDate][monthsAfterYearEnd]
        match = key.match(/rules\[(.*?)\]/)
        if match
          year = match[1]

          # Only process years that were selected
          if params["include_year_#{year}"] == "1"
            rules_to_apply[year] ||= {}

            # Extract the rest of the parameter key
            rule_part = key.sub("rules[#{year}]", '')

            # Build a nested structure based on the parameter key
            current = rules_to_apply[year]
            parts = rule_part.scan(/\[(.*?)\]/).flatten

            # Navigate to the correct location in the nested structure
            parts.each_with_index do |part, index|
              if index == parts.length - 1
                # This is the last part, set the value
                current[part] = value
              else
                # This is an intermediate part, ensure the nested structure exists
                current[part] ||= {}
                current = current[part]
              end
            end
          end
        end
      end
    end

    # Group rules by their configuration
    grouped_rules = {}

    rules_to_apply.each do |year, rule|
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

      flash[:notice] = "Successfully added AI-generated rules."
    else
      flash[:alert] = "Error updating form rules."
    end

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