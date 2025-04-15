class CreateJobs < ActiveRecord::Migration[8.0]
  def change
    create_table :jobs do |t|
      t.string :name
      t.date :coverage_start_date
      t.date :coverage_end_date

      t.timestamps
    end
  end
end
