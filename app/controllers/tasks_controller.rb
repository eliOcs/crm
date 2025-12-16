class TasksController < ApplicationController
  include InlineEditable

  inline_editable :name, :description, :status

  def index
    @tasks = Current.user.tasks.includes(:contact, :company).order(created_at: :desc)
    @tasks_by_status = @tasks.group_by(&:status)
  end

  def show
    @task = Current.user.tasks.find(params[:id])
  end

  def update
    @task = Current.user.tasks.find(params[:id])
    inline_update(@task)
  end
end
