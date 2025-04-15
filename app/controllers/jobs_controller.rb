class JobsController < ApplicationController
  def index
    @jobs = Job.all
  end

  def show
    @job = Job.find(params[:id])
    @job_forms = @job.job_forms
  end

  def new
    @job = Job.new
  end

  def create
    @job = Job.new(job_params)

    if @job.save
      redirect_to @job, notice: 'Job was successfully created.'
    else
      render :new
    end
  end

  def destroy
    @job = Job.find(params[:id])
    @job.destroy
    redirect_to jobs_path, notice: 'Job was successfully deleted.'
  end

  private

  def job_params
    params.require(:job).permit(:name, :coverage_start_date, :coverage_end_date, :entity_type)
  end
end