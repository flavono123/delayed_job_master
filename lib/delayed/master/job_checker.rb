require_relative 'job_finder'

module Delayed
  class Master
    class JobChecker
      def initialize(master)
        @master = master
        @config = master.config
        @mlti_db = MultiDB.new(@master)
        @finder = JobFinder.new(@master)
        @monitor = Monitor.new
      end

      def check
        workers = []

        @mlti_db.start_thread do |spec_name|
          settings = @finder.find(model_for(spec_name))
          settings.each do |setting|
            @monitor.synchronize do
              workers << Worker.new(index: @master.workers.size + workers.size, database: spec_name, setting: setting)
            end
          end
        end

        workers
      end

      private

      def model_for(spec_name)
        Delayed::Master.const_get("DelayedJobMaster#{spec_name.capitalize}")
      end
    end

    class MultiDB
      def initialize(master)
        @config = master.config
        @spec_names = target_spec_names
        define_models
        extend_after_fork_callback
      end

      def start_thread
        threads = @spec_names.map do |spec_name|
          Thread.new(spec_name) do |spec_name|
            yield spec_name
          end
        end

        threads.each(&:join)
      end

      private

      def target_spec_names
        if @config.databases.nil? || @config.databases.empty?
          load_spec_names.select { |spec_name| has_delayed_job_table?(spec_name) }
        else
          @config.databases
        end
      end

      def load_spec_names
        if Rails::VERSION::MAJOR >= 6
          configs = ActiveRecord::Base.configurations.configs_for(env_name: Rails.env)
          configs.reject(&:replica?).map { |c| c.spec_name.to_sym }
        else
          [Rails.env.to_sym]
        end
      end

      def has_delayed_job_table?(spec_name)
        ActiveRecord::Base.establish_connection(spec_name)
        ActiveRecord::Base.connection.tables.include?('delayed_jobs')
      end

      def define_models
        @spec_names.each do |spec_name|
          klass = Class.new(Delayed::Job)
          klass_name = "DelayedJobMaster#{spec_name.capitalize}"
          unless Delayed::Master.const_defined?(klass_name)
            Delayed::Master.const_set(klass_name, klass)
            Delayed::Master.const_get(klass_name).establish_connection(spec_name)
          end
        end
      end

      def extend_after_fork_callback
        prc = @config.after_fork
        @config.after_fork do |master, worker|
          prc.call(master, worker)
          if worker.database && ActiveRecord::Base.connection_pool.spec.name != worker.database.to_s
            ActiveRecord::Base.establish_connection(worker.database)
          end
        end
      end
    end
  end
end
