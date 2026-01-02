class TasksController < ApplicationController
  include InlineEditable

  inline_editable :name, :description, :status, :due_date

  def index
    @tasks = Current.user.tasks.includes(:contact, :company).order(created_at: :desc)
    @tasks_by_status = @tasks.group_by(&:status)
    fresh_when @tasks
  end

  def show
    @task = Current.user.tasks.includes(:contact, :company).find(params[:id])
    fresh_when [ @task, @task.contact, @task.company ].compact
  end

  def update
    @task = Current.user.tasks.find(params[:id])
    inline_update(@task)
  end

  private

  def transform_value(field, value)
    case field
    when "due_date"
      value.present? ? Date.parse(value) : nil
    else
      super
    end
  end
end
