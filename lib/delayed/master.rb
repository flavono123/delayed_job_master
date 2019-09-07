require 'fileutils'
require 'logger'
require_relative 'master/version'
require_relative 'master/command'
require_relative 'master/callback'
require_relative 'master/worker'
require_relative 'master/worker_pool'
require_relative 'master/signal_handler'
require_relative 'master/job_counter'
require_relative 'master/util/file_reopener'

module Delayed
  class Master
    attr_reader :config, :logger, :workers

    def initialize(argv)
      @config = Command.new(argv).config
      @logger = setup_logger(@config.log_file, @config.log_level)
      @workers = []

      @signal_handler = SignalHandler.new(self)
      @worker_pool = WorkerPool.new(self, @config)
    end

    def run
      load_app
      show_config
      daemonize if @config.daemon

      create_pid_file
      @logger.info "started master #{Process.pid}"

      @signal_handler.register
      @worker_pool.init
      @worker_pool.monitor_while { stop? }

      remove_pid_file
      @logger.info "shut down master"
    end

    def load_app
      require File.join(@config.working_directory, 'config', 'environment')
      require_relative 'worker/extension'
    end

    def prepared?
      @worker_pool.prepared?
    end

    def quit
      kill_workers
      @stop = true
    end

    def stop
      @signal_handler.dispatch('TERM')
      @stop = true
    end

    def stop?
      @stop
    end

    def reopen_files
      @signal_handler.dispatch('USR1')
      @logger.info "reopening files..."
      Util::FileReopener.reopen
      @logger.info "reopened"
    end

    def restart
      @signal_handler.dispatch('USR2')
      @logger.info "restarting master..."
      exec(*([$0] + ARGV))
    end

    def kill_workers
      @signal_handler.dispatch('KILL')
    end

    def wait_workers
      Process.waitall
    end

    private

    def setup_logger(log_file, log_level)
      FileUtils.mkdir_p(File.dirname(log_file))
      logger = Logger.new(log_file)
      logger.level = log_level
      logger
    end

    def create_pid_file
      FileUtils.mkdir_p(File.dirname(@config.pid_file))
      File.write(@config.pid_file, Process.pid)
    end

    def remove_pid_file
      File.delete(@config.pid_file) if File.exist?(@config.pid_file)
    end

    def daemonize
      Process.daemon(true)
    end

    def show_config
      @config.workers.each do |setting|
        puts "#{setting.count} worker for '#{setting.queues.join(',')}' under #{setting.control} control"
      end
    end
  end
end
