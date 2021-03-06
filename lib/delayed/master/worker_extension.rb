module Delayed
  class Worker
    attr_accessor :master_logger, :max_memory
  end
end

require_relative 'plugins/memory_checker'
require_relative 'plugins/signal_handler'
require_relative 'plugins/status_notifier'

[
  Delayed::Master::Plugins::MemoryChecker,
  Delayed::Master::Plugins::SignalHandler,
  Delayed::Master::Plugins::StatusNotifier
].each do |plugin|
  unless Delayed::Worker.plugins.include?(plugin)
    Delayed::Worker.plugins << plugin
  end
end
