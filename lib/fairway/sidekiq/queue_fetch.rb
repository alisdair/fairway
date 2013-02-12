require "sidekiq/fetch"

module Fairway
  module Sidekiq
    class QueueFetch < ::Sidekiq::BasicFetch
      def initialize(queue_reader, &block)
        @queue_reader = queue_reader
        @message_to_job = block if block_given?
      end

      def retrieve_work
        ::Sidekiq.logger.debug "#{self.class.name}#retrieve_work"
        unit_of_work = nil

        fairway_queue, work = @queue_reader.pull

        if work
          decoded_work = JSON.parse(work)
          work = @message_to_job.call(fairway_queue, decoded_work).to_json if @message_to_job
          unit_of_work = UnitOfWork.new(decoded_work["queue"], work)
        end

        if unit_of_work
          ::Sidekiq.logger.debug "#{self.class.name}#retrieve_work got work"
        else
          ::Sidekiq.logger.debug "#{self.class.name}#retrieve_work got nil"
        end

        unit_of_work
      end
    end
  end
end
