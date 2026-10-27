# frozen_string_literal: true

class AddJobsFinishedAtToGoodJobBatches < ActiveRecord::Migration[7.1]
  def change
    # Moved to db/migrate/tables/good_job_batches.rb
    # These files are not squashed since good_job will recreate them otherwise when an update is done.
  end
end
