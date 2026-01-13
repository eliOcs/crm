class TasksController < ApplicationController
  include InlineEditable
  include ActionView::Helpers::TextHelper

  inline_editable :name, :status, :due_date

  def index
    @tasks = Current.user.tasks.includes(:contacts, :company).order(created_at: :desc)
    @tasks_by_status = @tasks.group_by(&:status)
    fresh_when @tasks
  end

  def show
    @task = Current.user.tasks.includes(:contacts, :company).find(params[:id])
    fresh_when [ @task, @task.contacts, @task.company ].flatten.compact
  end

  def edit_description
    @task = Current.user.tasks.find(params[:id])
    render partial: "shared/notes_editor", locals: { record: @task, field: :description }
  end

  def update
    @task = Current.user.tasks.find(params[:id])

    if params[:task]&.key?(:description)
      update_description(@task)
    else
      inline_update(@task)
    end
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

  def update_description(record)
    old_text = record.description&.to_plain_text.presence || ""

    if record.update(description: params[:task][:description])
      new_text = record.description&.to_plain_text.presence || ""

      record.audit_logs.create!(
        user: Current.user,
        action: "update",
        message: "Updated description via UI",
        field_changes: { "description" => { "from" => truncate(old_text, length: 100), "to" => truncate(new_text, length: 100) } },
        metadata: { source: "ui" }
      )

      redirect_to record
    else
      render partial: "shared/notes_editor", locals: { record: record, field: :description }, status: :unprocessable_entity
    end
  end
end
