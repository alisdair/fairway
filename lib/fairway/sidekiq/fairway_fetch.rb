module Fairway
  module Sidekiq
    class FairwayFetch < ::Sidekiq::BasicFetch
      attr_reader :queues

      def initialize(queues, &block)
        @queues = queues
        @message_to_job = block if block_given?
      end

      def retrieve_work(options = {})
        options = { blocking: true }.merge(options)

        ::Sidekiq.logger.debug "#{self.class.name}#retrieve_work"
        unit_of_work = nil

        fairway_queue, work = @queues.pull

        if work
          decoded_work = JSON.parse(work)

          if @message_to_job
            decoded_work = @message_to_job.call(fairway_queue, decoded_work)
            work         = decoded_work.to_json
          end

          unit_of_work = UnitOfWork.new(decoded_work["queue"], work)
        end

        if unit_of_work
          ::Sidekiq.logger.debug "#{self.class.name}#retrieve_work got work"
        else
          ::Sidekiq.logger.debug "#{self.class.name}#retrieve_work got nil"
          sleep 1 if options[:blocking]
        end

        unit_of_work
      end

      def ==(other)
        other.respond_to?(:queues) && queues == other.queues
      end
    end
  end
end
