class JobForm < ApplicationRecord
  belongs_to :job

  validates :form_number, presence: true
  validates :locality_type, presence: true
  validates :locality, presence: true

  # The entity_type should be automatically set from the job
  before_validation :set_entity_type_from_job

  private

  def set_entity_type_from_job
    self.entity_type = job.entity_type if job
  end
end