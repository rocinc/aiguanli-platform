# frozen_string_literal: true

require_relative "support"

module DemoSeed
  # Cosmetic repairs that keep the demo world readable: built-in query names that
  # the standard seeder writes in English, and leftover test queries.
  class Polish
    include Support

    QUERY_NAMES = {
      "Epic children: User stories and bugs" => "史诗的子项：用户故事与缺陷",
      "User story children: Tasks" => "用户故事的子项：任务"
    }.freeze

    # The planning meeting must still be ahead when the demo is recorded; the
    # seed puts it on Monday 10:00, which is already past on a Monday afternoon.
    def future_planning_meeting
      meeting = Meeting.find_by(title: "Sprint 7 计划会")
      return unless meeting

      day = Date.current + 1
      day += 1 while day.saturday? || day.sunday?
      target = Time.zone.parse("#{day} 10:00")
      return if meeting.start_time == target

      meeting.update_columns(start_time: target)
      say("Sprint 7 planning moved to #{day} 10:00")
    end

    # A saved team planner gives the module something real to open in the recording.
    def team_planner
      name = "Sprint 7 团队计划"
      query = Query.find_by(name:, project_id: project.id)
      unless query
        result = TeamPlanner::Views::GlobalCreateService.new(user: ctx.admin)
                                                       .call(name:, public: true, project_id: project.id)
        query = result.result.query if result.success?
      end
      return unless query

      query.filters = [{ "assigned_to_id" => { "operator" => "=", "values" => %w[30 31 34 35 33 37] } }]
      query.save!
      say("team planner ready")
    end

    # The acceptance baseline stores the My Page widgets' queries under a test
    # name; deleting those by name breaks every "assigned/created/watched"
    # widget. Rebuild a clean query per widget before the junk-name sweep.
    def repair_my_page_widgets
      User.current = ctx.admin
      Grids::MyPage.find_each do |grid|
        Grids::Widget.where(grid_id: grid.id).where("identifier LIKE 'work_packages%'").each do |widget|
          existing = Query.find_by(id: widget.options["queryId"].to_s)
          next if existing && !existing.name.to_s.start_with?("!!!")

          filters = [{ "status_id" => { "operator" => "o", "values" => [] } }]
          case widget.identifier
          when "work_packages_assigned" then filters << { "assigned_to_id" => { "operator" => "=", "values" => ["me"] } }
          when "work_packages_created" then filters << { "author_id" => { "operator" => "=", "values" => ["me"] } }
          when "work_packages_accountable" then filters << { "responsible_id" => { "operator" => "=", "values" => ["me"] } }
          when "work_packages_watched" then filters << { "watcher_id" => { "operator" => "=", "values" => ["me"] } }
          end
          name = widget.options["name"].presence || "工作包表"
          query = Query.create!(name:, user_id: grid.user_id, filters:, include_subprojects: false,
                                column_names: %w[id project type subject status])
          widget.options = widget.options.merge("queryId" => query.id.to_s)
          widget.save!
        end
      end
    rescue StandardError => e
      say("my page widgets skipped: #{e.class} #{e.message.truncate(100)}")
    end

    def call
      QUERY_NAMES.each do |from, to|
        Query.where(name: from).update_all(name: to)
      end
      repair_my_page_widgets
      Query.where("name LIKE ?", "%!!!%").delete_all
      future_planning_meeting
      team_planner
      say("queries cleaned")
    end
  end
end
