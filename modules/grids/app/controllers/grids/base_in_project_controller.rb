module ::Grids
  class BaseInProjectController < ::ApplicationController
    before_action :find_project_by_project_id
    before_action :authorize

    def show
      render
    end
  end
end
