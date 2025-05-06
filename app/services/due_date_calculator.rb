# app/services/due_date_calculator.rb

class DueDateCalculator
  def initialize(forms_repository = nil)
    @forms_repository = forms_repository || FormsRepository.new
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

    return nil unless rule

    # Calculate dates using the rule
    calculate_specific_dates(rule, coverage_start_date, coverage_end_date, base_date)
  end

  # New method to calculate dates from a rule directly (used by AI suggestions preview)
  def calculate_specific_dates(rule, start_date, end_date, base_date = nil)
    # Default to end date as base if not specified
    base_date ||= end_date

    # Get month of base date for fiscal year exception checking
    base_month = base_date.month.to_s.rjust(2, '0')

    # Calculate due date
    due_date = nil
    if rule['dueDate']
      due_date = calculate_date(rule['dueDate'], base_date, base_month, end_date.year)
    end

    # Calculate extension date
    extension_due_date = nil
    if rule['extensionDueDate']
      extension_due_date = calculate_date(rule['extensionDueDate'], base_date, base_month, end_date.year)
    end

    {
      due_date: due_date,
      extension_due_date: extension_due_date
    }
  end

  private

  def find_applicable_rule(form, tax_year)
    return nil unless form['calculationRules']

    # Try to find exact year match first
    exact_match = form['calculationRules'].find do |rule|
      rule['effectiveYears'] && rule['effectiveYears'].include?(tax_year)
    end

    return exact_match if exact_match

    # If no exact match, find closest year
    closest_rule = nil
    closest_year_diff = Float::INFINITY

    form['calculationRules'].each do |rule|
      next unless rule['effectiveYears']&.any?

      rule['effectiveYears'].each do |year|
        year_diff = (year - tax_year).abs
        if year_diff < closest_year_diff
          closest_year_diff = year_diff
          closest_rule = rule.merge('approximated' => true)
        end
      end
    end

    closest_rule
  end

  def calculate_date(date_rule, base_date, base_month, year)
    # Default values
    months_to_add = 0
    day_of_month = date_rule['dayOfMonth'] || 15
    reference_date = base_date

    # Check for fiscal year exceptions first
    if date_rule['fiscalYearExceptions'] && date_rule['fiscalYearExceptions'][base_month]
      exception = date_rule['fiscalYearExceptions'][base_month]

      if exception['monthsAfterYearEnd']
        months_to_add = exception['monthsAfterYearEnd']
      elsif exception['monthsAfterYearStart']
        months_to_add = exception['monthsAfterYearStart']
        reference_date = Date.new(year, 1, 1)
      end

      day_of_month = exception['dayOfMonth'] if exception['dayOfMonth']
    else
      # Use standard rules
      if date_rule['monthsAfterYearEnd']
        months_to_add = date_rule['monthsAfterYearEnd']
      elsif date_rule['monthsAfterYearStart']
        months_to_add = date_rule['monthsAfterYearStart']
        reference_date = Date.new(year, 1, 1)
      end
    end

    # Calculate the result date using safe Date arithmetic
    calculate_result_date(reference_date, months_to_add, day_of_month)
  end

  def calculate_result_date(reference_date, months_to_add, day_of_month)
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