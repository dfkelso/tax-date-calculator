# app/services/claude_service.rb
class ClaudeService
  def initialize(api_key = nil)
    @api_key = api_key || ENV['ANTHROPIC_API_KEY']

    # Create client with access_token parameter
    @client = Anthropic::Client.new(access_token: @api_key)
  end

  def generate_tax_rules(form_data)
    prompt = build_tax_rule_prompt(form_data)

    begin
      # Use messages method to create a message
      response = @client.messages(
        model: "claude-3-opus-20240229",
        max_tokens: 4096,
        messages: [
          { role: "user", content: prompt }
        ]
      )

      # Parse the JSON response from Claude
      parse_response(response.content)
    rescue => e
      Rails.logger.error("Error calling Anthropic API: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      nil
    end
  end

  def generate_missing_years(form_data, missing_years, existing_rules)
    prompt = build_missing_years_prompt(form_data, missing_years, existing_rules)

    begin
      # Use messages method to create a message
      response = @client.messages(
        model: "claude-3-opus-20240229",
        max_tokens: 4096,
        messages: [
          { role: "user", content: prompt }
        ]
      )

      # Parse the JSON response from Claude
      parse_response(response.content)
    rescue => e
      Rails.logger.error("Error calling Anthropic API for missing years: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      nil
    end
  end

  private

  def build_tax_rule_prompt(form_data)
    current_year = Date.today.year
    seven_years_ago = current_year - 6

    <<~PROMPT
    You are an expert tax form researcher specializing in due dates for tax forms across multiple jurisdictions. 
    I need you to determine the due dates and extension due dates for the following tax form for the past 7 years (#{seven_years_ago}..#{current_year}):

    Form Number: #{form_data[:form_number]}
    Form Name: #{form_data[:form_name]}
    Entity Type: #{form_data[:entity_type]}
    Locality Type: #{form_data[:locality_type]}
    Locality: #{form_data[:locality]}

    Please provide the calculation rules for each year. If there were changes to due dates in certain years (like during COVID-19), make sure to account for those.

    Respond with a JSON object that follows this structure:
    ```json
    {
      "calculationRules": [
        {
          "effectiveYears": [2023, 2024],
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

    Ensure your response is valid JSON that can be directly used in our application.
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

    Respond with a JSON object that follows this structure:
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

    Ensure your response is valid JSON that can be directly used in our application.
    PROMPT
  end

  def parse_response(response_text)
    # Extract the JSON part from Claude's response
    json_match = response_text.match(/```json\n(.*?)\n```/m)
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