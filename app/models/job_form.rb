class JobForm < ApplicationRecord
  belongs_to :job

  validates :form_number, presence: true
  validates :entity_type, presence: true
  validates :locality_type, presence: true
  validates :locality, presence: true
end