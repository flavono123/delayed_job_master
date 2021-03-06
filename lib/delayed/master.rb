require 'fileutils'
require 'logger'
require_relative 'master/version'
require_relative 'master/command'
require_relative 'master/worker'
require_relative 'master/monitoring'
require_relative 'master/signaler'
require_relative 'master/util/file_reopener'

module Delayed
  class Master
    attr_reader :config, :logger, :workers

    def initialize(argv)
      @config = Command.new(argv).config
      @logger = setup_logger(@config.log_file, @config.log_level)
      @workers = []

      @signaler = Signaler.new(self)
      @monitoring = Monitoring.new(self)
    end

    def run
      print_config
      daemonize if @config.daemon

      @logger.info "started master #{Process.pid}".tap { |msg| puts msg }

      handle_pid_file do
        @signaler.register
        @prepared = true
        @monitoring.monitor_while { stop? }
      end

      @logger.info "shut down master"
    end

    def prepared?
      @prepared
    end

    def quit
      @signaler.dispatch(:KILL)
      @stop = true
    end

    def stop
      @signaler.dispatch(:TERM)
      @stop = true
    end

    def stop?
      @stop == true
    end

    def reopen_files
      @signaler.dispatch(:USR1)
      @logger.info "reopening files..."
      Util::FileReopener.reopen
      @logger.info "reopened"
    end

    def restart
      @signaler.dispatch(:USR2)
      @logger.info "restarting master..."
      exec(*([$0] + ARGV))
    end

    private

    def setup_logger(log_file, log_level)
      FileUtils.mkdir_p(File.dirname(log_file)) if log_file.is_a?(String)
      logger = Logger.new(log_file)
      logger.level = log_level
      logger
    end
  
    def daemonize
      Process.daemon(true)
    end

    def handle_pid_file
      create_pid_file
      yield
      remove_pid_file
    end

    def create_pid_file
      FileUtils.mkdir_p(File.dirname(@config.pid_file))
      File.write(@config.pid_file, Process.pid)
    end

    def remove_pid_file
      File.delete(@config.pid_file) if File.exist?(@config.pid_file)
    end

    def print_config
      @logger.info "databases: #{@config.databases.join(', ')}" if @config.databases
      @config.worker_settings.each do |setting|
        message = "worker[#{setting.id}]: #{setting.count} processes"
        message << " (#{setting.queues.join(', ')})" if setting.queues.respond_to?(:join)
        @logger.info message
      end
    end
  end
end
