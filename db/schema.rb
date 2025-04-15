# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2025_04_15_132541) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "job_forms", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "form_number"
    t.string "entity_type"
    t.string "locality_type"
    t.string "locality"
    t.date "due_date"
    t.date "extension_due_date"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["job_id"], name: "index_job_forms_on_job_id"
  end

  create_table "jobs", force: :cascade do |t|
    t.string "name"
    t.date "coverage_start_date"
    t.date "coverage_end_date"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "entity_type"
  end

  add_foreign_key "job_forms", "jobs"
end
