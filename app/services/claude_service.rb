# app/services/claude_service.rb
require 'net/http'
require 'uri'
require 'json'

class ClaudeService
  def initialize(api_key = nil)
    @api_key = api_key || ENV['ANTHROPIC_API_KEY']
  end

  def generate_tax_rules(form_data)
    prompt = build_tax_rule_prompt(form_data)

    response = make_claude_request(prompt)
    result = parse_response(response)

    # Improve the response by calculating actual dates for each rule
    calculate_example_dates(result, form_data) if result

    result
  end

  def generate_missing_years(form_data, missing_years, existing_rules)
    prompt = build_missing_years_prompt(form_data, missing_years, existing_rules)

    response = make_claude_request(prompt)
    result = parse_response(response)

    # Add example dates here too
    calculate_example_dates(result, form_data) if result

    result
  end

  private

  def make_claude_request(prompt)
    uri = URI.parse('https://api.anthropic.com/v1/messages')
    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = 'application/json'
    request['X-Api-Key'] = @api_key
    request['anthropic-version'] = '2023-06-01'

    request.body = {
      model: 'claude-3-opus-20240229',
      max_tokens: 4000,
      messages: [
        { role: 'user', content: prompt }
      ]
    }.to_json

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 180  # Increase timeout to 3 minutes to avoid timeouts

    begin
      response = http.request(request)

      if response.code == '200'
        Rails.logger.info("Claude API success: #{response.code}")
        JSON.parse(response.body)['content'].first['text']
      else
        Rails.logger.error("Claude API error: #{response.code} - #{response.body}")
        nil
      end
    rescue => e
      Rails.logger.error("Error making Claude API request: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      nil
    end
  end

  # Calculate example dates for each rule to show what the actual dates would be
  def calculate_example_dates(result, form_data)
    return unless result && result['calculationRules']

    calculator = DueDateCalculator.new

    # Current tax year as the sample year for date calculations
    tax_year = Date.today.year

    result['calculationRules'].each do |rule|
      # For each rule, add sample dates
      start_date = Date.new(tax_year, 1, 1)
      end_date = Date.new(tax_year, 12, 31)

      # Calculate sample dates using the rule
      dates = calculator.calculate_specific_dates(rule, start_date, end_date)

      # Add the calculated example dates to the rule
      rule['exampleDates'] = {
        'year': tax_year,
        'dueDate': dates[:due_date]&.strftime('%B %d, %Y'),
        'extensionDueDate': dates[:extension_due_date]&.strftime('%B %d, %Y')
      }
    end
  end

  def build_tax_rule_prompt(form_data)
    current_year = Date.today.year
    seven_years_ago = current_year - 6

    <<~PROMPT
    You are a senior tax compliance specialist with expert knowledge of filing deadlines across all IRS forms, state tax forms, and local tax forms. 

    I need you to research and determine the exact due dates and extension due dates for the following tax form for each year from #{seven_years_ago} through #{current_year + 1}:

    Form Number: #{form_data[:form_number]}
    Form Name: #{form_data[:form_name]}
    Entity Type: #{form_data[:entity_type]}
    Locality Type: #{form_data[:locality_type]}
    Locality: #{form_data[:locality]}

    RESEARCH GUIDELINES:
    1. Use multiple official sources to verify deadlines. Primary sources like IRS.gov, state tax department websites, and official tax calendars are most reliable.
    2. For each year, determine both the standard filing deadline and the maximum extension deadline.
    3. Pay special attention to any COVID-19 related changes in 2020-2021, as many tax deadlines were extended.
    4. Account for any changes to standard filing deadlines that occurred over the past 7 years.
    5. Consider any special rules that apply to the specific entity type (#{form_data[:entity_type]}).
    6. For fiscal year entities, note any different rules that apply to different fiscal year ends.
    7. Account for weekend/holiday adjustments in your base calculations.
    8. For foreign entity forms, take into account any special international filing rules.

    IMPORTANT: Your research should be thorough and accurate. Ensure that for each year, you find the exact month and day when forms are due, accounting for regulatory changes, special extensions, and unique circumstances.

    FORMAT YOUR RESPONSE AS VALID JSON:
    ```json
    {
      "calculationRules": [
        {
          "effectiveYears": [2020],
          "dueDate": {
            "monthsAfterYearEnd": 7,
            "dayOfMonth": 15
          },
          "extensionDueDate": {
            "monthsAfterYearEnd": 11,
            "dayOfMonth": 15
          }
        },
        {
          "effectiveYears": [2019, 2021, 2022, 2023, 2024, 2025, 2026],
          "dueDate": {
            "monthsAfterYearEnd": 5,
            "dayOfMonth": 15
          },
          "extensionDueDate": {
            "monthsAfterYearEnd": 11,
            "dayOfMonth": 15
          }
        }
      ]
    }
    ```

    GROUPING RULES:
    - Group years that have identical filing requirements together.
    - Years with different requirements (like 2020 COVID extensions) should be in separate rule objects.
    - If certain fiscal year endings have different rules (common for corporate returns), use fiscalYearExceptions like:
    ```
    "fiscalYearExceptions": {
      "06": {  // For June fiscal year end
        "monthsAfterYearEnd": 4,
        "dayOfMonth": 15
      }
    }
    ```

    CALCULATION BASES:
    - Most tax due dates are calculated as "monthsAfterYearEnd" 
    - If you discover that dates should be calculated from the beginning of the year, use "monthsAfterYearStart" instead

    RULES FOR DETERMINING CALCULATIONS:
    - Use standard tax calculation practices - typically X months after the end of the tax year
    - If a form uses a different calculation approach, implement it according to official guidance
    - Always include the day of the month when the form is due
    - For forms with unusual timing requirements, ensure the calculation method accurately reflects official deadlines

    Provide ONLY the JSON result with no additional explanation. The JSON must be valid, properly formatted, and contain accurate tax filing information based on thorough research.
  PROMPT
  end

  def build_missing_years_prompt(form_data)
    <<~PROMPT
    You are a senior tax compliance specialist with expert knowledge of filing deadlines across all IRS forms, state tax forms, and local tax forms. 

    I need you to research and determine the exact due dates and extension due dates for the following tax form for ONLY these specific missing years: #{form_data[:missing_years].join(', ')}.

    Form Number: #{form_data[:form_number]}
    Form Name: #{form_data[:form_name]}
    Entity Type: #{form_data[:entity_type]}
    Locality Type: #{form_data[:locality_type]}
    Locality: #{form_data[:locality]}

    The form already has rules for these years: #{form_data[:existing_years].join(', ')}
    These are the existing calculation rules: 
    #{JSON.pretty_generate(form_data[:existing_rules] || [])}

    RESEARCH GUIDELINES:
    1. Use multiple official sources to verify deadlines. Primary sources like IRS.gov, state tax department websites, and official tax calendars are most reliable.
    2. For each MISSING year, determine both the standard filing deadline and the maximum extension deadline.
    3. Pay special attention to any COVID-19 related changes in 2020-2021, as many tax deadlines were extended.
    4. Account for any changes to standard filing deadlines that have occurred.
    5. Consider any special rules that apply to the specific entity type (#{form_data[:entity_type]}).
    6. For fiscal year entities, note any different rules that apply to different fiscal year ends.
    7. Account for weekend/holiday adjustments in your base calculations.

    IMPORTANT: Your research should be thorough and accurate. Ensure that for each missing year, you find the exact month and day when forms are due, accounting for regulatory changes, special extensions, and unique circumstances.

    FORMAT YOUR RESPONSE AS VALID JSON:
    ```json
    {
      "calculationRules": [
        {
          "effectiveYears": [2019],
          "dueDate": {
            "monthsAfterYearEnd": 5,
            "dayOfMonth": 15
          },
          "extensionDueDate": {
            "monthsAfterYearEnd": 11,
            "dayOfMonth": 15
          }
        }
      ]
    }
    ```

    GROUPING RULES:
    - Group missing years that have identical filing requirements together.
    - Years with different requirements should be in separate rule objects.
    - ONLY include the missing years I've specified.
    - If certain fiscal year endings have different rules, use fiscalYearExceptions like:
    ```
    "fiscalYearExceptions": {
      "06": {  // For June fiscal year end
        "monthsAfterYearEnd": 4,
        "dayOfMonth": 15
      }
    }
    ```

    CONSISTENCY WITH EXISTING RULES:
    - Your new rules for missing years should be consistent with the patterns in existing rules.
    - If an existing rule applies to 2021-2023 and you're providing rules for 2019, 
      make sure there's a good reason if your rule differs from the 2021-2023 pattern.

    CALCULATION BASES:
    - Most tax due dates are calculated as "monthsAfterYearEnd" 
    - If you discover that dates should be calculated from the beginning of the year, use "monthsAfterYearStart" instead

    RULES FOR DETERMINING CALCULATIONS:
    - Use standard tax calculation practices - typically X months after the end of the tax year
    - If a form uses a different calculation approach, implement it according to official guidance
    - Always include the day of the month when the form is due
    - For forms with unusual timing requirements, ensure the calculation method accurately reflects official deadlines

    Provide ONLY the JSON result with no additional explanation. The JSON must be valid, properly formatted, and contain only rules for the missing years.
  PROMPT
  end

  def parse_response(response_text)
    return nil unless response_text

    # Extract the JSON part from Claude's response
    json_match = response_text.match(/```(?:json)?\s*([\s\S]*?)\s*```/)
    return nil unless json_match

    json_str = json_match[1]
    begin
      JSON.parse(json_str)
    rescue JSON::ParserError => e
      # Handle parsing errors
      Rails.logger.error("Failed to parse Claude response: #{e.message}")
      nil
    end
  end
end