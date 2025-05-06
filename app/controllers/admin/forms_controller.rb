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
      # Store form info and missing years in session for the confirmation page
      session[:form_id] = params[:id]
      session[:missing_years] = missing_years
      session[:form_details] = {
        'formNumber' => @form['formNumber'],
        'formName' => @form['formName'],
        'entityType' => @form['entityType'],
        'localityType' => @form['localityType'],
        'locality' => @form['locality']
      }

      # Generate rule suggestions for the missing years
      suggested_rules = generate_rule_suggestions(@form, missing_years)
      session[:suggested_rules] = suggested_rules

      # Redirect to confirmation page
      redirect_to confirm_missing_years_admin_form_path(params[:id])
    else
      flash[:notice] = "No missing years to fill. All years from #{earliest_year} to #{latest_year} are covered."
      redirect_to edit_admin_form_path(params[:id])
    end
  end

  # AI-assisted rule generation
  def generate_ai_rules
    return redirect_to admin_forms_path, alert: 'Form not found.' unless @form

    # Get the form details for the prompt
    form_details = {
      'formNumber' => @form['formNumber'],
      'formName' => @form['formName'],
      'entityType' => @form['entityType'],
      'localityType' => @form['localityType'],
      'locality' => @form['locality'],
      'extension' => @form['extension']
    }

    # Generate years to cover (last 7 years through next year)
    current_year = Date.today.year
    years_to_cover = ((current_year - 7)..current_year + 1).to_a

    # Call Claude API to get suggestions
    suggestions = claude_api_tax_rules(form_details, years_to_cover)

    if suggestions
      # Store suggestions in session for confirmation page
      session[:form_id] = params[:id]
      session[:suggested_years] = years_to_cover
      session[:form_details] = form_details
      session[:suggested_rules] = suggestions

      # Redirect to confirmation page
      redirect_to confirm_ai_rules_admin_form_path(params[:id])
    else
      flash[:alert] = "Failed to generate rule suggestions. Please try again."
      redirect_to edit_admin_form_path(params[:id])
    end
  end

  def confirm_ai_rules
    # Display confirmation page with suggested rules
    @form_id = session[:form_id]
    @years = session[:suggested_years]
    @form_details = session[:form_details]
    @suggested_rules = session[:suggested_rules]

    # Make sure we have all the required data
    unless @form_id && @years && @form_details && @suggested_rules
      flash[:alert] = "Missing data for confirmation. Please try again."
      redirect_to edit_admin_form_path(params[:id])
    end
  end

  def apply_ai_rules
    # Get data from params
    form_id = params[:id]
    rules_to_apply = JSON.parse(params[:rules]) if params[:rules].present?

    unless form_id && rules_to_apply
      flash[:alert] = "Missing data for applying rules. Please try again."
      redirect_to edit_admin_form_path(form_id)
      return
    end

    # Get the form
    @form = @form_manager.find_form(form_id)

    unless @form
      flash[:alert] = "Form not found."
      redirect_to admin_forms_path
      return
    end

    # Clear existing rules if requested
    @form['calculationRules'] = [] if params[:replace_existing] == "1"
    @form['calculationRules'] ||= []

    # Group rules by their configuration to avoid duplication
    grouped_rules = {}

    rules_to_apply.each do |year, rule|
      # Create a key based on the rule configuration
      key = rule_config_key(rule)

      # Initialize the group if it doesn't exist
      grouped_rules[key] ||= {
        'rule' => rule,
        'years' => []
      }

      # Add the year to this group
      grouped_rules[key]['years'] << year.to_i
    end

    # Create one rule per unique configuration with all applicable years
    grouped_rules.each do |_, group_data|
      rule = group_data['rule']
      rule['effectiveYears'] = group_data['years'].sort
      @form['calculationRules'] << rule
    end

    # Save the updated form
    if @form_manager.update_form(form_id, @form)
      # Clear session data
      session.delete(:form_id)
      session.delete(:suggested_years)
      session.delete(:form_details)
      session.delete(:suggested_rules)

      flash[:notice] = "Successfully added AI-generated rules."
    else
      flash[:alert] = "Error updating form rules."
    end

    redirect_to edit_admin_form_path(form_id)
  end

  def confirm_missing_years
    # Display confirmation page with suggested rules
    @form_id = session[:form_id]
    @missing_years = session[:missing_years]
    @form_details = session[:form_details]
    @suggested_rules = session[:suggested_rules]

    # Make sure we have all the required data
    unless @form_id && @missing_years && @form_details && @suggested_rules
      flash[:alert] = "Missing data for confirmation. Please try again."
      redirect_to edit_admin_form_path(params[:id])
      return
    end
  end

  def apply_missing_years
    # Get data from params
    form_id = params[:id]
    rules_to_apply = JSON.parse(params[:rules]) if params[:rules].present?

    unless form_id && rules_to_apply
      flash[:alert] = "Missing data for applying rules. Please try again."
      redirect_to edit_admin_form_path(form_id)
      return
    end

    # Get the form
    @form = @form_manager.find_form(form_id)

    unless @form
      flash[:alert] = "Form not found."
      redirect_to admin_forms_path
      return
    end

    # Apply the new rules
    @form['calculationRules'] ||= []

    # Group rules by their configuration
    grouped_rules = {}

    rules_to_apply.each do |year, rule|
      # Create a key based on the rule configuration
      key = rule_config_key(rule)

      # Initialize the group if it doesn't exist
      grouped_rules[key] ||= {
        'rule' => rule,
        'years' => []
      }

      # Add the year to this group
      grouped_rules[key]['years'] << year.to_i
    end

    # Create one rule per unique configuration with all applicable years
    grouped_rules.each do |_, group_data|
      rule = group_data['rule']
      rule['effectiveYears'] = group_data['years'].sort
      @form['calculationRules'] << rule
    end

    # Save the updated form
    if @form_manager.update_form(form_id, @form)
      # Clear session data
      session.delete(:form_id)
      session.delete(:missing_years)
      session.delete(:form_details)
      session.delete(:suggested_rules)

      flash[:notice] = "Successfully added rules for the missing years."
    else
      flash[:alert] = "Error updating form rules."
    end

    redirect_to edit_admin_form_path(form_id)
  end

  def export_json
    form_manager = JsonFormManager.new
    send_data form_manager.export_json,
              type: 'application/json',
              disposition: 'attachment',
              filename: "tax_forms_#{Date.today.strftime('%Y%m%d')}.json"
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

    form_data
  end

  def generate_rule_suggestions(form, missing_years)
    # Default rule suggestions based on entity type and locality
    suggested_rules = {}

    missing_years.each do |year|
      # Create a base rule structure
      rule = {}

      # Set due dates based on entity type and locality
      case form['entityType']
      when 'individual'
        rule['dueDate'] = {'monthsAfterYearEnd' => 4, 'dayOfMonth' => 15}
        rule['extensionDueDate'] = {'monthsAfterYearEnd' => 10, 'dayOfMonth' => 15}
      when 'corporation'
        rule['dueDate'] = {
          'monthsAfterYearEnd' => 3,
          'dayOfMonth' => 15,
          'fiscalYearExceptions' => {
            '06' => {
              'monthsAfterYearEnd' => 4,
              'dayOfMonth' => 15
            }
          }
        }
        rule['extensionDueDate'] = {
          'monthsAfterYearEnd' => 9,
          'dayOfMonth' => 15,
          'fiscalYearExceptions' => {
            '06' => {
              'monthsAfterYearEnd' => 10,
              'dayOfMonth' => 15
            }
          }
        }
      when 'partnership', 'scorp'
        rule['dueDate'] = {'monthsAfterYearEnd' => 3, 'dayOfMonth' => 15}
        rule['extensionDueDate'] = {'monthsAfterYearEnd' => 9, 'dayOfMonth' => 15}
      when 'smllc'
        if form['localityType'] == 'federal'
          rule['dueDate'] = {'monthsAfterYearEnd' => 4, 'dayOfMonth' => 15}
          rule['extensionDueDate'] = {'monthsAfterYearEnd' => 10, 'dayOfMonth' => 15}
        else
          rule['dueDate'] = {'monthsAfterYearEnd' => 3, 'dayOfMonth' => 15}
          rule['extensionDueDate'] = {'monthsAfterYearEnd' => 9, 'dayOfMonth' => 15}
        end
      else
        rule['dueDate'] = {'monthsAfterYearEnd' => 4, 'dayOfMonth' => 15}
        rule['extensionDueDate'] = {'monthsAfterYearEnd' => 10, 'dayOfMonth' => 15}
      end

      suggested_rules[year.to_s] = rule
    end

    suggested_rules
  end

  def rule_config_key(rule)
    # Create a unique key based on rule configuration
    key = "#{rule['dueDate']['monthsAfterYearEnd']}-#{rule['dueDate']['dayOfMonth']}"
    key += "-#{rule['extensionDueDate']['monthsAfterYearEnd']}-#{rule['extensionDueDate']['dayOfMonth']}" if rule['extensionDueDate']

    # Add fiscal year exceptions to the key if they exist
    if rule['dueDate']['fiscalYearExceptions']
      rule['dueDate']['fiscalYearExceptions'].each do |month, exception|
        key += "-#{month}-#{exception['monthsAfterYearEnd']}-#{exception['dayOfMonth']}"

        # Add extension exceptions if they exist
        if rule['extensionDueDate'] && rule['extensionDueDate']['fiscalYearExceptions'] &&
          rule['extensionDueDate']['fiscalYearExceptions'][month]
          ext = rule['extensionDueDate']['fiscalYearExceptions'][month]
          key += "-ext-#{month}-#{ext['monthsAfterYearEnd']}-#{ext['dayOfMonth']}"
        end
      end
    end

    key
  end

  def claude_api_tax_rules(form_details, years)
    require 'net/http'
    require 'uri'
    require 'json'

    # Construct a prompt for Claude API
    prompt = <<~PROMPT
    You are an expert tax consultant specializing in tax filing dates. I need your help to determine the correct filing and extension due dates for a tax form with the following details:

    Form Number: #{form_details['formNumber']}
    Form Name: #{form_details['formName']}
    Entity Type: #{form_details['entityType']}
    Locality Type: #{form_details['localityType']}
    Locality: #{form_details['locality']}
    #{form_details['extension'] ? "Extension Form: #{form_details['extension']['formNumber']} - #{form_details['extension']['formName']}" : "No extension form specified"}
    #{form_details['extension'] && form_details['extension']['piggybackFed'] ? "Uses federal extension (piggyback)" : ""}

    For each of the tax years #{years.join(', ')}, please provide:
    1. The normal filing due date (month and day)
    2. The extension due date (month and day)
    3. Any fiscal year exceptions (especially for entities with June year-end)
    4. Any special rules or considerations for this specific form

    Please format your response as a JSON object with each year as a key. Consider any exceptional circumstances such as COVID-19 extensions for 2019, 2020, and 2021 tax years, disaster relief extensions, or weekend/holiday adjustments.
    PROMPT

    # For development without actual API, return reasonable defaults
    # In production, you would call the Claude API here with the prompt

    # Create reasonable defaults based on the form details
    suggested_rules = {}

    years.each do |year|
      # Create a base rule structure
      rule = {}

      # Set due dates based on entity type and locality
      case form_details['entityType']
      when 'individual'
        rule['dueDate'] = {'monthsAfterYearEnd' => 4, 'dayOfMonth' => 15}
        rule['extensionDueDate'] = {'monthsAfterYearEnd' => 10, 'dayOfMonth' => 15}

        # Handle COVID extensions for 2019, 2020, 2021
        if year == 2019
          rule['dueDate'] = {'monthsAfterYearEnd' => 7, 'dayOfMonth' => 15} # July 15, 2020 for 2019 returns
        elsif year == 2020
          rule['dueDate'] = {'monthsAfterYearEnd' => 5, 'dayOfMonth' => 17} # May 17, 2021 for 2020 returns
        elsif year == 2021
          rule['dueDate'] = {'monthsAfterYearEnd' => 4, 'dayOfMonth' => 18} # April 18, 2022 for 2021 returns
        end

      when 'corporation'
        rule['dueDate'] = {
          'monthsAfterYearEnd' => 3,
          'dayOfMonth' => 15,
          'fiscalYearExceptions' => {
            '06' => {
              'monthsAfterYearEnd' => 4,
              'dayOfMonth' => 15
            }
          }
        }
        rule['extensionDueDate'] = {
          'monthsAfterYearEnd' => 9,
          'dayOfMonth' => 15,
          'fiscalYearExceptions' => {
            '06' => {
              'monthsAfterYearEnd' => 10,
              'dayOfMonth' => 15
            }
          }
        }

        # Handle COVID extensions for corporations
        if year == 2019 && form_details['localityType'] == 'federal'
          rule['dueDate']['monthsAfterYearEnd'] = 7
          rule['dueDate']['dayOfMonth'] = 15
          if rule['dueDate']['fiscalYearExceptions'] && rule['dueDate']['fiscalYearExceptions']['06']
            rule['dueDate']['fiscalYearExceptions']['06']['monthsAfterYearEnd'] = 7
            rule['dueDate']['fiscalYearExceptions']['06']['dayOfMonth'] = 15
          end
        end

      when 'partnership', 'scorp'
        rule['dueDate'] = {'monthsAfterYearEnd' => 3, 'dayOfMonth' => 15}
        rule['extensionDueDate'] = {'monthsAfterYearEnd' => 9, 'dayOfMonth' => 15}

        # Handle COVID extensions
        if year == 2019 && form_details['localityType'] == 'federal'
          rule['dueDate'] = {'monthsAfterYearEnd' => 7, 'dayOfMonth' => 15}
        end

      when 'smllc'
        if form_details['localityType'] == 'federal'
          rule['dueDate'] = {'monthsAfterYearEnd' => 4, 'dayOfMonth' => 15}
          rule['extensionDueDate'] = {'monthsAfterYearEnd' => 10, 'dayOfMonth' => 15}
        else
          # State-specific default
          rule['dueDate'] = {'monthsAfterYearEnd' => 3, 'dayOfMonth' => 15}
          rule['extensionDueDate'] = {'monthsAfterYearEnd' => 9, 'dayOfMonth' => 15}
        end

        # Handle COVID extensions
        if year == 2019 && form_details['localityType'] == 'federal'
          rule['dueDate'] = {'monthsAfterYearEnd' => 7, 'dayOfMonth' => 15}
        end
      else
        # Default fallback
        rule['dueDate'] = {'monthsAfterYearEnd' => 4, 'dayOfMonth' => 15}
        rule['extensionDueDate'] = {'monthsAfterYearEnd' => 10, 'dayOfMonth' => 15}
      end

      # Special handling for specific states
      if form_details['localityType'] == 'state'
        case form_details['locality']
        when 'California'
          # Match federal due dates
          if year == 2019
            rule['dueDate'] = {'monthsAfterYearEnd' => 7, 'dayOfMonth' => 15}
          elsif year == 2020
            rule['dueDate'] = {'monthsAfterYearEnd' => 5, 'dayOfMonth' => 17}
          end
        when 'Texas'
          # Texas has specific franchise tax dates
          if ['corporation', 'scorp', 'partnership', 'smllc'].include?(form_details['entityType'])
            rule['dueDate'] = {'monthsAfterYearStart' => 5, 'dayOfMonth' => 15}
            rule['extensionDueDate'] = {'monthsAfterYearStart' => 11, 'dayOfMonth' => 15}
          end
        end
      end

      # Store the suggested rule for this year
      suggested_rules[year.to_s] = rule
    end

    suggested_rules
  end
end