class Delayed::Plugins::SignalHandler < Delayed::Plugin
  callbacks do |lifecycle|
    lifecycle.before(:execute) do |worker|
      worker.instance_eval do
        trap('USR1') do
          Thread.new do
            master_logger.info "reopening files..."
            Delayed::Util.reopen_files
            master_logger.info "reopened"
          end
        end
        trap('USR2') do
          Thread.new do
            $0 = "#{$0} [OLD]"
            master_logger.info "shutting down #{Process.pid}..."
            stop
          end
        end
      end
    end
    lifecycle.after(:execute) do |worker|
      worker.master_logger.info "shut down #{Process.pid}"
    end
  end
end

Delayed::Worker.plugins << Delayed::Plugins::SignalHandler