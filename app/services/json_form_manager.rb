class JsonFormManager
  def initialize(json_path = Rails.root.join('config', 'forms.json'))
    @json_path = json_path
    @data = load_json
  end

  def all_forms
    @data['forms']
  end

  def find_form(id)
    id = id.to_i
    index = id - 1
    return nil if index < 0 || index >= all_forms.length
    all_forms[index]
  end

  def add_form(form_data)
    @data['forms'] << form_data
    save_json
  end

  def update_form(id, form_data)
    id = id.to_i
    index = id - 1  # Convert ID to array index

    Rails.logger.info("Updating form at index #{index}")
    Rails.logger.info("Form data before updating: #{@data['forms'][index].inspect}")

    return false if index < 0 || index >= @data['forms'].length

    # Deep copy using JSON serialization to avoid reference issues
    form_data_copy = JSON.parse(form_data.to_json)

    # Ensure calculationRules is an array
    form_data_copy['calculationRules'] ||= []

    # Update the form in the data structure
    @data['forms'][index] = form_data_copy

    Rails.logger.info("Form data after updating: #{@data['forms'][index].inspect}")

    # Save changes to file
    save_json
  end

  def delete_form(id)
    id = id.to_i
    index = id - 1
    return false if index < 0 || index >= all_forms.length

    @data['forms'].delete_at(index)
    save_json
  end

  # Add this method to the JsonFormManager class
  def delete_calculation_rule(form_id, rule_index)
    form_id = form_id.to_i
    form_index = form_id - 1
    rule_index = rule_index.to_i

    Rails.logger.info("Deleting rule #{rule_index} from form #{form_id} (index #{form_index})")

    # Ensure form exists
    return false if form_index < 0 || form_index >= @data['forms'].length

    # Get the form
    form = @data['forms'][form_index]

    # Ensure form has calculationRules array
    form['calculationRules'] ||= []

    # Ensure rule index is valid
    return false if rule_index < 0 || rule_index >= form['calculationRules'].length

    # Remove the rule
    form['calculationRules'].delete_at(rule_index)

    # Save changes
    Rails.logger.info("After deletion, form has #{form['calculationRules'].length} rules")
    save_json
  end


  def export_json
    JSON.pretty_generate(@data)
  end

  def import_json(json_string)
    begin
      @data = JSON.parse(json_string)
      save_json
      true
    rescue => e
      Rails.logger.error("Error importing JSON: #{e.message}")
      false
    end
  end

  private

  def load_json
    JSON.parse(File.read(@json_path))
  rescue => e
    Rails.logger.error("Error loading JSON: #{e.message}")
    { 'forms' => [] }
  end

  # In app/services/json_form_manager.rb
  def save_json
    # Make absolutely sure we're writing to the right file
    Rails.logger.info("Writing JSON to: #{@json_path}")
    Rails.logger.info("JSON content size: #{@data['forms'].size}")

    # Print the content of the form we're trying to update
    form_index = 29  # Form 30 is at index 29
    if form_index < @data['forms'].size
      Rails.logger.info("Form 30 calculation rules before save: #{@data['forms'][form_index]['calculationRules'].inspect}")
    end

    # Write with explicit options
    File.open(@json_path, 'w') do |file|
      file.write(JSON.pretty_generate(@data))
    end

    # Verify the file was written
    Rails.logger.info("File exists after save: #{File.exist?(@json_path)}")
    Rails.logger.info("File size after save: #{File.size(@json_path)} bytes")

    # Reload to verify save worked
    begin
      temp_data = JSON.parse(File.read(@json_path))
      Rails.logger.info("Successfully read back JSON with #{temp_data['forms'].size} forms")

      # Verify the form was updated in the file
      if form_index < temp_data['forms'].size
        Rails.logger.info("Form 30 calculation rules after reload: #{temp_data['forms'][form_index]['calculationRules'].inspect}")
      end
    rescue => e
      Rails.logger.error("Error reloading JSON: #{e.message}")
      return false
    end

    true
  end
end