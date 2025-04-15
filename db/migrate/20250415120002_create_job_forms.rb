class CreateJobForms < ActiveRecord::Migration[8.0]
  def change
    create_table :job_forms do |t|
      t.references :job, null: false, foreign_key: true
      t.string :form_number
      t.string :entity_type
      t.string :locality_type
      t.string :locality
      t.date :due_date
      t.date :extension_due_date

      t.timestamps
    end
  end
end
