class JobFormsController < ApplicationController
  before_action :set_job
  before_action :load_form_options, only: [:new]

  def index
    @job_forms = @job.job_forms
  end

  def new
    @job_form = @job.job_forms.build
  end

  def create
    @job_form = @job.job_forms.build(job_form_params)

    # Calculate due dates using our service
    calculator = DueDateCalculator.new
    dates = calculator.calculate_dates(
      @job_form.form_number,
      @job.entity_type, # Use the job's entity type instead of the form's
      @job_form.locality_type,
      @job_form.locality,
      @job.coverage_start_date,
      @job.coverage_end_date
    )

    if dates
      @job_form.due_date = dates[:due_date]
      @job_form.extension_due_date = dates[:extension_due_date]
    end

    if @job_form.save
      redirect_to job_path(@job), notice: 'Form was successfully added to job.'
    else
      load_form_options
      render :new
    end
  end

  def destroy
    @job_form = @job.job_forms.find(params[:id])
    @job_form.destroy
    redirect_to job_path(@job), notice: 'Form was successfully deleted.'
  end

  private

  def set_job
    @job = Job.find(params[:job_id])
  end

  def job_form_params
    params.require(:job_form).permit(:form_number, :locality_type, :locality)
  end

  def load_form_options
    forms_repo = FormsRepository.new

    # Filter form numbers based on job's entity type
    @available_form_numbers = forms_repo.all_forms
                                        .select { |form| form['entityType'] == @job.entity_type }
                                        .map { |form| form['formNumber'] }
                                        .uniq

    # Get available locality types for radio buttons
    @available_locality_types = forms_repo.all_forms
                                          .select { |form| form['entityType'] == @job.entity_type }
                                          .map { |form| form['localityType'] }
                                          .uniq

    # Initialize with all localities (will be filtered via JavaScript)
    @available_localities = forms_repo.all_forms
                                      .select { |form| form['entityType'] == @job.entity_type }
                                      .map { |form| form['locality'] }
                                      .uniq
  end
end

# Add these methods to the JobFormsController
def localities
  forms_repo = FormsRepository.new
  localities = forms_repo.all_forms
                         .select { |form| form['entityType'] == params[:entity_type] && form['localityType'] == params[:locality_type] }
                         .map { |form| form['locality'] }
                         .uniq

  render json: localities
end

def form_numbers
  forms_repo = FormsRepository.new
  form_numbers = forms_repo.all_forms
                           .select { |form|
                             form['entityType'] == params[:entity_type] &&
                               form['localityType'] == params[:locality_type] &&
                               form['locality'] == params[:locality]
                           }
                           .map { |form| form['formNumber'] }
                           .uniq

  render json: form_numbers
end