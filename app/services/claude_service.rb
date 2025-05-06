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
    You are an expert tax form researcher specializing in due dates for tax forms across multiple jurisdictions. 
    I need you to determine the due dates and extension due dates for the following tax form for the past 7 years (#{seven_years_ago}..#{current_year}) plus next year:

    Form Number: #{form_data[:form_number]}
    Form Name: #{form_data[:form_name]}
    Entity Type: #{form_data[:entity_type]}
    Locality Type: #{form_data[:locality_type]}
    Locality: #{form_data[:locality]}

    Please provide the calculation rules for each year. If there were changes to due dates in certain years (like during COVID-19 in 2020), make sure to account for those.

    Please follow this exact JSON format in your response:
    ```json
    {
      "calculationRules": [
        {
          "effectiveYears": [2023, 2024, 2025],
          "dueDate": {
            "monthsAfterYearEnd": 4,
            "dayOfMonth": 15
          },
          "extensionDueDate": {
            "monthsAfterYearEnd": 10,
            "dayOfMonth": 15
          }
        },
        {
          "effectiveYears": [2020],
          "dueDate": {
            "monthsAfterYearEnd": 7,
            "dayOfMonth": 15
          },
          "extensionDueDate": {
            "monthsAfterYearEnd": 10,
            "dayOfMonth": 15
          }
        }
      ]
    }
    ```

    Group years with identical rules together. For any fiscal year exceptions (like corporations with June year-ends), include those under fiscalYearExceptions in the appropriate format, like:
    ```
    "fiscalYearExceptions": {
      "06": {
        "monthsAfterYearEnd": 4,
        "dayOfMonth": 15
      }
    }
    ```

    Ensure your response is valid JSON that can be directly used in our application. Do not include any explanation or commentary outside the JSON code block.
    PROMPT
  end

  def build_missing_years_prompt(form_data, missing_years, existing_rules)
    <<~PROMPT
    You are an expert tax form researcher specializing in due dates for tax forms across multiple jurisdictions. 
    I need you to determine the due dates and extension due dates for the following tax form for specific missing years: #{missing_years.join(', ')}.

    Form Number: #{form_data[:form_number]}
    Form Name: #{form_data[:form_name]}
    Entity Type: #{form_data[:entity_type]}
    Locality Type: #{form_data[:locality_type]}
    Locality: #{form_data[:locality]}

    Here are the existing calculation rules for this form:
    #{JSON.pretty_generate(existing_rules)}

    Please provide the calculation rules ONLY for the missing years. Note that some years may have had different due dates (like during COVID-19 in 2020), so make sure to account for those.

    Please follow this exact JSON format in your response:
    ```json
    {
      "calculationRules": [
        {
          "effectiveYears": [2019, 2021, 2022],
          "dueDate": {
            "monthsAfterYearEnd": 4,
            "dayOfMonth": 15
          },
          "extensionDueDate": {
            "monthsAfterYearEnd": 10,
            "dayOfMonth": 15
          }
        },
        {
          "effectiveYears": [2020],
          "dueDate": {
            "monthsAfterYearEnd": 7,
            "dayOfMonth": 15
          },
          "extensionDueDate": {
            "monthsAfterYearEnd": 10,
            "dayOfMonth": 15
          }
        }
      ]
    }
    ```

    Group years with identical rules together. For any fiscal year exceptions (like corporations with June year-ends), include those under fiscalYearExceptions in the appropriate format.

    Ensure your response is valid JSON that can be directly used in our application. Do not include any explanation or commentary outside the JSON code block.
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