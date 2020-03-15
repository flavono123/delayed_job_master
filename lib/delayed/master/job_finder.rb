# JobCounter depends on delayed_job_active_record.
# See https://github.com/collectiveidea/delayed_job_active_record/blob/master/lib/delayed/backend/active_record.rb
module Delayed
  class Master
    class JobFinder
      def initialize(master)
        @master = master
        @config = master.config
        @available_settings = find_available_settings
        @monitor = Monitor.new
      end

      def find(model)
        jobs = find_jobs(model)

        jobs.each_with_object([]) do |job, array|
          @monitor.synchronize do
            @available_settings.each_with_index do |setting, i|
              if Matcher.new(model, job, setting).match?
                array << setting
                @available_settings.delete_at(i)
                break
              end
            end
          end
        end
      end

      private

      def find_available_settings
        @config.worker_settings.each_with_object([]) do |setting, array|
          count = @master.workers.count { |worker| worker.setting.id == setting.id }
          (setting.count - count).times do
            array << setting
          end
        end
      end

      def find_jobs(model)
        db_time_now = model.db_time_now
        model.select(:id, :queue, :priority, :locked_at).where("run_at <= ? AND failed_at IS NULL", db_time_now)
      end
    end

    class Matcher
      def initialize(model, job, setting)
        @model = model
        @job = job
        @setting = setting
      end

      def match?
        max_run_time? && priority? && queue?
      end

      private

      def max_run_time?
        max_run_time = @setting.max_run_time || Delayed::Worker::DEFAULT_MAX_RUN_TIME
        !@job.locked_at || @job.locked_at + max_run_time < @model.db_time_now
      end

      def priority?
        !@job.priority ||
          ((!@setting.min_priority || @setting.min_priority <= @job.priority) &&
           (!@setting.max_priority || @setting.max_priority >= @job.priority))
      end

      def queue?
        @setting.queues.empty? || @setting.queues.include?(@job.queue)
      end
    end
  end
end
