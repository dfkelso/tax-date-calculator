class JsonFormManager
  def initialize(json_path = Rails.root.join('config', 'forms.json'))
    @json_path = json_path
    @data = load_json
  end

  def all_forms
    @data['forms']
  end

  def find_form(id)
    form_index = id.to_i - 1
    return nil if form_index < 0 || form_index >= all_forms.length
    all_forms[form_index]
  end

  def add_form(form_data)
    @data['forms'] << form_data
    save_json
    true
  rescue
    false
  end

  def update_form(id, form_data)
    form_index = id.to_i - 1
    return false if form_index < 0 || form_index >= all_forms.length

    # Ensure deep cloning of the data
    @data['forms'][form_index] = deep_clone(form_data)
    save_json
    true
  rescue => e
    Rails.logger.error("Error updating form: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    false
  end

  private

  def deep_clone(obj)
    JSON.parse(obj.to_json)
  end

  def delete_form(id)
    form_index = id.to_i - 1
    return false if form_index < 0 || form_index >= all_forms.length

    @data['forms'].delete_at(form_index)
    save_json
    true
  rescue
    false
  end

  def add_calculation_rule(form_id, rule_data)
    form = find_form(form_id)
    return false unless form

    form['calculationRules'] ||= []
    form['calculationRules'] << rule_data
    save_json
    true
  rescue => e
    puts "Error adding calculation rule: #{e.message}"
    false
  end

  def update_calculation_rule(form_id, rule_index, rule_data)
    form = find_form(form_id)
    return false unless form
    return false unless form['calculationRules'] && rule_index.to_i < form['calculationRules'].length

    form['calculationRules'][rule_index.to_i] = rule_data
    save_json
    true
  rescue => e
    puts "Error updating calculation rule: #{e.message}"
    false
  end

  def delete_calculation_rule(form_id, rule_index)
    form = find_form(form_id)
    return false unless form
    return false unless form['calculationRules'] && rule_index.to_i < form['calculationRules'].length

    form['calculationRules'].delete_at(rule_index.to_i)
    save_json
    true
  rescue => e
    puts "Error deleting calculation rule: #{e.message}"
    false
  end

  def export_json
    JSON.pretty_generate(@data)
  end

  def import_json(json_string)
    begin
      @data = JSON.parse(json_string)
      save_json
      true
    rescue JSON::ParserError => e
      puts "Error parsing JSON: #{e.message}"
      false
    end
  end

  private

  def load_json
    JSON.parse(File.read(@json_path))
  rescue Errno::ENOENT, JSON::ParserError => e
    puts "Error loading JSON: #{e.message}"
    { 'forms' => [] }
  end

  def save_json
    File.write(@json_path, JSON.pretty_generate(@data))
  end
end