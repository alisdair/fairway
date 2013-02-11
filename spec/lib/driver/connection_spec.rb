require "spec_helper"

module Driver
  describe Connection do
    let(:config) do
      Driver.config.tap do |c|
        c.namespace = "driver:backbone"

        c.facet do |message|
          message[:facet]
        end
      end
    end
    let(:connection) { Connection.new(config) }
    let(:redis)  { config.redis }

    let(:message) { { facet: 1, topic: "event:helloworld" } }

    describe "#initialize" do
      it "registers queues from the config" do
        config = Config.new
        config.register_queue("myqueue", ".*")
        config.redis.hgetall("registered_queues").should == {}
        Connection.new(config)

        config.redis.hgetall("registered_queues").should == {
          "myqueue" => ".*"
        }
      end

      context "when an existing queue definition does not match" do
        it "raises a QueueMismatchError"
      end
    end

    describe "#deliver" do
      it "publishes message over the message topic channel" do
        redis = Redis.new

        redis.psubscribe("*:event:helloworld") do |on|
          on.psubscribe do |pattern, total|
            connection.deliver(message)
          end

          on.pmessage do |pattern, channel, received_message|
            received_message.should == message.to_json
            channel.should == "#{config.redis.namespace}:event:helloworld"
            redis.punsubscribe(pattern)
          end
        end
      end

      context "registered queue exists for message type" do
        before do
          config.register_queue("myqueue", "event:helloworld")
        end

        it "adds message to the environment facet for the queue" do
          connection.deliver(message)
          redis.llen("myqueue:1").should == 1
          redis.lindex("myqueue:1", 0).should == message.to_json
        end

        it "adds facet to list of active facets" do
          connection.deliver(message)
          redis.smembers("myqueue:active_facets").should == ["1"]
        end

        it "pushes facet onto facet queue" do
          connection.deliver(message)
          redis.llen("myqueue:facet_queue").should == 1
          redis.lindex("myqueue:facet_queue", 0).should == "1"
        end

        it "doesn't push onto to facet queue if currently active" do
          redis.sadd("myqueue:active_facets", "1")
          connection.deliver(message)
          redis.llen("myqueue:facet_queue").should == 0
        end
      end

      context "multiple queues exist for message type" do
        before do
          config.register_queue("myqueue", ".*:helloworld")
          config.register_queue("yourqueue", "event:.*world")
        end

        it "adds message for both queues" do
          connection.deliver(message)
          redis.llen("myqueue:1").should == 1
          redis.llen("yourqueue:1").should == 1
        end
      end

      context "registered queue exists for another message type" do
        before do
          config.register_queue("myqueue", "email:helloworld")
        end

        it "doesn't add message to the queue" do
          connection.deliver(message)
          redis.llen("myqueue:1").should == 0
        end

        it "doesn't add facet to list of active facets" do
          connection.deliver(message)
          redis.smembers("myqueue:active_facets").should == []
        end
      end
    end

    describe "#pull" do
      before do
        config.register_queue("myqueue", "event:helloworld")
      end

      it "pulls a message off the queue using FIFO strategy" do
        connection.deliver(message1 = message.merge(message: 1))
        connection.deliver(message2 = message.merge(message: 2))

        connection.pull("myqueue").should == message1.to_json
        connection.pull("myqueue").should == message2.to_json
      end

      it "pulls from facets of the queue in a round-robin nature" do
        connection.deliver(message1 = message.merge(facet: 1, message: 1))
        connection.deliver(message2 = message.merge(facet: 1, message: 2))
        connection.deliver(message3 = message.merge(facet: 2, message: 3))

        connection.pull("myqueue").should == message1.to_json
        connection.pull("myqueue").should == message3.to_json
        connection.pull("myqueue").should == message2.to_json
      end

      it "removes facet from active list if it becomes empty" do
        connection.deliver(message)

        redis.smembers("myqueue:active_facets").should == ["1"]
        connection.pull("myqueue")
        redis.smembers("myqueue:active_facets").should be_empty
      end

      it "returns nil if there are no messages to retrieve" do
        connection.deliver(message)

        connection.pull("myqueue").should == message.to_json
        connection.pull("myqueue").should be_nil
      end

      context "pulling from multiple queues" do
        before do
          config.register_queue("myqueue1", "event:1")
          config.register_queue("myqueue2", "event:2")
        end

        it "pulls messages off first queue with a message" do
          connection.deliver(message1 = message.merge(topic: "event:1"))
          connection.deliver(message2 = message.merge(topic: "event:2"))

          connection.pull(["myqueue2", "myqueue1"]).should == message2.to_json
          connection.pull(["myqueue2", "myqueue1"]).should == message1.to_json
        end

        it "returns nil if no queues have messages" do
          connection.pull(["myqueue2", "myqueue1"]).should be_nil
        end

        it "pulls from facets of the queue in a round-robin nature" do
          connection.deliver(message1 = message.merge(facet: 1, topic: "event:1"))
          connection.deliver(message2 = message.merge(facet: 1, topic: "event:1"))
          connection.deliver(message3 = message.merge(facet: 2, topic: "event:1"))
          connection.deliver(message4 = message.merge(facet: 1, topic: "event:2"))

          connection.pull(["myqueue2", "myqueue1"]).should == message4.to_json
          connection.pull(["myqueue2", "myqueue1"]).should == message1.to_json
          connection.pull(["myqueue2", "myqueue1"]).should == message3.to_json
          connection.pull(["myqueue2", "myqueue1"]).should == message2.to_json
        end
      end
    end
  end
end
