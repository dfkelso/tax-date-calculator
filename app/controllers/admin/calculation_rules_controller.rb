class Admin::CalculationRulesController < Admin::BaseController
  before_action :set_form
  before_action :set_rule, only: [:edit, :update, :destroy]

  def new
    @rule = {}
  end

  def create
    rule_data = prepare_rule_params

    if @form_manager.add_calculation_rule(params[:form_id], rule_data)
      redirect_to edit_admin_form_path(params[:form_id]), notice: 'Calculation rule was successfully added.'
    else
      flash.now[:alert] = 'Error adding calculation rule.'
      render :new
    end
  end

  def edit
  end

  def update
    rule_data = prepare_rule_params

    if @form_manager.update_calculation_rule(params[:form_id], params[:id], rule_data)
      redirect_to edit_admin_form_path(params[:form_id]), notice: 'Calculation rule was successfully updated.'
    else
      flash.now[:alert] = 'Error updating calculation rule.'
      render :edit
    end
  end

  def destroy
    if @form_manager.delete_calculation_rule(params[:form_id], params[:id])
      redirect_to edit_admin_form_path(params[:form_id]), notice: 'Calculation rule was successfully deleted.'
    else
      redirect_to edit_admin_form_path(params[:form_id]), alert: 'Error deleting calculation rule.'
    end
  end

  private

  def set_form
    @form_manager = JsonFormManager.new
    @form = @form_manager.find_form(params[:form_id])

    redirect_to admin_forms_path, alert: 'Form not found.' unless @form
  end

  def set_rule
    rule_index = params[:id].to_i
    if @form['calculationRules'] && rule_index < @form['calculationRules'].length
      @rule = @form['calculationRules'][rule_index]
    else
      redirect_to edit_admin_form_path(params[:form_id]), alert: 'Rule not found.'
    end
  end

  def prepare_rule_params
    effective_years = params[:effective_years].split(',').map(&:strip).map(&:to_i)

    rule_data = {
      'effectiveYears' => effective_years,
      'dueDate' => {
        'monthsAfterYearEnd' => params[:due_months_after_year_end].to_i,
        'dayOfMonth' => params[:due_day_of_month].to_i
      }
    }

    # Add extension due date if present
    if params[:extension_months_after_year_end].present?
      rule_data['extensionDueDate'] = {
        'monthsAfterYearEnd' => params[:extension_months_after_year_end].to_i,
        'dayOfMonth' => params[:extension_day_of_month].to_i
      }
    end

    # Add fiscalYearExceptions if present
    if params[:fiscal_year_exception_month].present?
      month = params[:fiscal_year_exception_month].to_s.rjust(2, '0')
      rule_data['dueDate']['fiscalYearExceptions'] = {
        month => {
          'monthsAfterYearEnd' => params[:fiscal_due_months_after_year_end].to_i,
          'dayOfMonth' => params[:fiscal_due_day_of_month].to_i
        }
      }

      if params[:fiscal_extension_months_after_year_end].present?
        rule_data['extensionDueDate'] ||= {}
        rule_data['extensionDueDate']['fiscalYearExceptions'] = {
          month => {
            'monthsAfterYearEnd' => params[:fiscal_extension_months_after_year_end].to_i,
            'dayOfMonth' => params[:fiscal_extension_day_of_month].to_i
          }
        }
      end
    end

    rule_data
  end
end