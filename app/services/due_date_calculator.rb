class DueDateCalculator
  def initialize(forms_repository = FormsRepository.new)
    @forms_repository = forms_repository
  end

  def calculate_dates(form_number, entity_type, locality_type, locality, coverage_start_date, coverage_end_date)
    form = @forms_repository.find_form(form_number, entity_type, locality_type, locality)
    return nil unless form

    # Determine base date based on calculation base
    calculation_base = form['calculationBase'] || 'end'
    base_date = calculation_base == 'end' ? coverage_end_date : coverage_start_date

    # Find rule for the specific tax year
    tax_year = coverage_end_date.year
    rule = find_applicable_rule(form, tax_year)

    if !rule
      puts "No applicable rule found for year #{tax_year}"
      return nil
    end

    # Get month of base date for fiscal year exception checking
    base_month = base_date.month.to_s.rjust(2, '0')

    # Calculate due date
    due_date = nil
    if rule['dueDate']
      due_date = calculate_specific_date(rule['dueDate'], base_date, base_month)
    end

    # Calculate extension date
    extension_due_date = nil
    if rule['extensionDueDate']
      extension_due_date = calculate_specific_date(rule['extensionDueDate'], base_date, base_month)
    end

    {
      due_date: due_date,
      extension_due_date: extension_due_date
    }
  end

  private

  def find_applicable_rule(form, tax_year)
    return nil unless form['calculationRules']

    form['calculationRules'].find do |rule|
      rule['effectiveYears'] && rule['effectiveYears'].include?(tax_year)
    end
  end

  def calculate_specific_date(date_rule, base_date, base_month)
    # Default variables
    months_to_add = 0
    day_of_month = 15 # Default

    # Check for fiscal year exceptions first
    if date_rule['fiscalYearExceptions'] && date_rule['fiscalYearExceptions'][base_month]
      exception = date_rule['fiscalYearExceptions'][base_month]

      if exception['monthsAfterYearEnd']
        months_to_add = exception['monthsAfterYearEnd']
        reference_date = base_date
      elsif exception['monthsAfterYearStart']
        months_to_add = exception['monthsAfterYearStart']
        reference_date = Date.new(base_date.year, 1, 1)
      end

      day_of_month = exception['dayOfMonth'] if exception['dayOfMonth']

      # Otherwise use standard rules
    else
      if date_rule['monthsAfterYearEnd']
        months_to_add = date_rule['monthsAfterYearEnd']
        reference_date = base_date
      elsif date_rule['monthsAfterYearStart']
        months_to_add = date_rule['monthsAfterYearStart']
        reference_date = Date.new(base_date.year, 1, 1)
      end

      day_of_month = date_rule['dayOfMonth'] if date_rule['dayOfMonth']
    end

    # Calculate the result date using safe Date arithmetic
    year = reference_date.year + ((reference_date.month + months_to_add - 1) / 12)
    month = ((reference_date.month + months_to_add - 1) % 12) + 1

    # Ensure valid day for month (handle cases like Feb 30)
    max_day = Date.new(year, month, -1).day
    day = [day_of_month, max_day].min

    result_date = Date.new(year, month, day)

    # Adjust for weekends and holidays
    while [0, 6].include?(result_date.wday) || holiday?(result_date)
      result_date = result_date.next_day
    end

    result_date
  end

  def holiday?(date)
    # This is a placeholder for holiday checking logic
    # In a real implementation, you would check if the date is a federal holiday
    false
  end
end