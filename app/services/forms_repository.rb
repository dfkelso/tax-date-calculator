class FormsRepository
  def initialize(json_path = Rails.root.join('config', 'forms.json'))
    @forms_data = JSON.parse(File.read(json_path))
    @forms = @forms_data['forms']
  end

  def find_form(form_number, entity_type, locality_type, locality)
    @forms.find do |form|
      form['formNumber'] == form_number &&
        form['entityType'] == entity_type &&
        form['localityType'] == locality_type &&
        form['locality'] == locality
    end
  end

  def all_forms
    @forms
  end

  def available_form_numbers
    @forms.map { |form| form['formNumber'] }.uniq
  end

  def available_entity_types
    @forms.map { |form| form['entityType'] }.uniq
  end

  def available_locality_types
    @forms.map { |form| form['localityType'] }.uniq
  end

  def available_localities
    @forms.map { |form| form['locality'] }.uniq
  end
end