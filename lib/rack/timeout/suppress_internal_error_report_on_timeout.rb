module Rack
  class Timeout
    module SuppressInternalErrorReportOnTimeout
      def op_handle_error(message_or_exception, context = {})
        if respond_to?(:request) && request.env[Rack::Timeout::ENV_INFO_KEY].try(:state) == :timed_out
          Rails.logger.error "Rack::Timeout: Receiving timeout exception: #{message_or_exception}"
          return
        end

        super
      end
    end
  end
end
