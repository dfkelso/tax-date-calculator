class DueDateCalculator
  def initialize(forms_repository = FormsRepository.new)
    @forms_repository = forms_repository
  end

  def calculate_dates(form_number, entity_type, locality_type, locality, coverage_start_date, coverage_end_date)
    form = @forms_repository.find_form(form_number, entity_type, locality_type, locality)
    return nil unless form

    year_end = coverage_end_date
    year_start = coverage_start_date
    calculation_base = form['calculationBase'] || 'end'

    # Find rule for the tax year
    tax_year = coverage_end_date.year
    rule = find_applicable_rule(form, tax_year)
    return nil unless rule

    # Calculate due date based on calculation base
    base_date = calculation_base == 'end' ? year_end : year_start

    # Get month of year-end for fiscal year exception checking
    year_end_month = base_date.month.to_s.rjust(2, '0')

    # Calculate due date
    due_date = calculate_specific_date(rule['dueDate'], base_date, year_end_month)

    # Calculate extension date if extension data exists
    extension_due_date = nil
    if rule['extensionDueDate']
      extension_due_date = calculate_specific_date(rule['extensionDueDate'], base_date, year_end_month)
    end

    {
      due_date: due_date,
      extension_due_date: extension_due_date
    }
  end

  private

  def find_applicable_rule(form, tax_year)
    form['calculationRules'].find do |rule|
      rule['effectiveYears'].include?(tax_year)
    end
  end

  def calculate_specific_date(date_rule, base_date, year_end_month)
    # Check for fiscal year exceptions
    if date_rule['fiscalYearExceptions'] && date_rule['fiscalYearExceptions'][year_end_month]
      exception_rule = date_rule['fiscalYearExceptions'][year_end_month]
      months_after = exception_rule['monthsAfterYearEnd'] || date_rule['monthsAfterYearEnd']
      day = exception_rule['dayOfMonth'] || date_rule['dayOfMonth']
    else
      # Handle monthsAfterYearStart if present, otherwise use monthsAfterYearEnd
      if date_rule['monthsAfterYearStart']
        months_after = date_rule['monthsAfterYearStart']
        base_date = base_date.beginning_of_year  # Reset to beginning of year if using monthsAfterYearStart
      else
        months_after = date_rule['monthsAfterYearEnd']
      end
      day = date_rule['dayOfMonth']
    end

    # Add months to the base date
    result_date = base_date + months_after.months

    # Set the specific day of month
    result_date = result_date.change(day: day)

    # Adjust for weekends and holidays (simplified)
    while [0, 6].include?(result_date.wday) || holiday?(result_date)
      result_date = result_date.next_day
    end

    result_date
  end

  def holiday?(date)
    # Implement holiday checking logic
    # This would check for federal holidays and adjust accordingly
    false # Simplified for this example
  end
end