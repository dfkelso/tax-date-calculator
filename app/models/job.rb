class Job < ApplicationRecord
  has_many :job_forms, dependent: :destroy

  validates :name, presence: true
  validates :coverage_start_date, presence: true
  validates :coverage_end_date, presence: true
end