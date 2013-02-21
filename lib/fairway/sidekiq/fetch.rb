module Fairway
  module Sidekiq
    class Fetch
      class Fetches
        attr_reader :list

        def from(queue, weight = 1)
          queue = BasicFetch.new(::Sidekiq.options) if queue == :sidekiq

          weight.times do
            list << queue
          end
        end

        def list
          @list ||= []
        end
      end

      def initialize(&block)
        yield(@fetches = Fetches.new)
      end

      def new
        self
      end

      def fetches
        @fetches.list
      end

      def fetch_order
        fetches.shuffle.uniq
      end

      def retrieve_work
        ::Sidekiq.logger.debug "#{self.class.name}#retrieve_work"

        fetch_order.each do |fetch|
          work = fetch.retrieve_work(blocking: false)

          if work
            ::Sidekiq.logger.debug "#{self.class.name}#retrieve_work got work"
            return work
          end
        end

        ::Sidekiq.logger.debug "#{self.class.name}#retrieve_work got nil"
        sleep 1

        return nil
      end
    end
  end
end
