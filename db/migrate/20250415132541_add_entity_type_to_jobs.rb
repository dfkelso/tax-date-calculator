class AddEntityTypeToJobs < ActiveRecord::Migration[8.0]
  def change
    add_column :jobs, :entity_type, :string
  end
end
