require "spec_helper"

module Fairway
  describe Queue do
    let(:connection) do
      c = Connection.new(Fairway.config)
      ChanneledConnection.new(c) do |message|
        message[:topic]
      end
    end
    let(:message)     { { facet: 1, topic: "event:helloworld" } }

    describe "#initialize" do
      it "requires a Connection and queue names" do
        lambda { Queue.new }.should raise_error(ArgumentError)
      end
    end

    describe "#length" do
      let(:queue) { Queue.new(connection, "myqueue") }

      before do
        Fairway.config.register_queue("myqueue", "event:helloworld")
      end

      it "returns the number of queued messages across facets" do
        queue.length.should == 0

        connection.deliver(message.merge(facet: 1, message: 1))
        connection.deliver(message.merge(facet: 1, message: 2))
        connection.deliver(message.merge(facet: 2, message: 3))

        queue.length.should == 3

        queue.pull
        queue.pull
        queue.pull

        queue.length.should == 0
      end
    end

    describe "#pull" do
      before do
        Fairway.config.register_queue("myqueue", "event:helloworld")
      end

      it "pulls a message off the queue using FIFO strategy" do
        connection.deliver(message1 = message.merge(message: 1))
        connection.deliver(message2 = message.merge(message: 2))

        queue = Queue.new(connection, "myqueue")
        queue.pull.should == ["myqueue", message1.to_json]
        queue.pull.should == ["myqueue", message2.to_json]
      end

      it "pulls from facets of the queue in a round-robin nature" do
        connection.deliver(message1 = message.merge(facet: 1, message: 1))
        connection.deliver(message2 = message.merge(facet: 1, message: 2))
        connection.deliver(message3 = message.merge(facet: 2, message: 3))

        queue = Queue.new(connection, "myqueue")
        queue.pull.should == ["myqueue", message1.to_json]
        queue.pull.should == ["myqueue", message3.to_json]
        queue.pull.should == ["myqueue", message2.to_json]
      end

      it "removes facet from active list if it becomes empty" do
        connection.deliver(message)

        Fairway.config.redis.smembers("myqueue:active_facets").should == ["1"]
        queue = Queue.new(connection, "myqueue")
        queue.pull
        Fairway.config.redis.smembers("myqueue:active_facets").should be_empty
      end

      it "returns nil if there are no messages to retrieve" do
        connection.deliver(message)

        queue = Queue.new(connection, "myqueue")
        queue.pull.should == ["myqueue", message.to_json]
        queue.pull.should be_nil
      end

      context "pulling from multiple queues" do
        before do
          Fairway.config.register_queue("myqueue1", "event:1")
          Fairway.config.register_queue("myqueue2", "event:2")
        end

        it "pulls messages off first queue with a message" do
          connection.deliver(message1 = message.merge(topic: "event:1"))
          connection.deliver(message2 = message.merge(topic: "event:2"))

          queue = Queue.new(connection, "myqueue2", "myqueue1")
          queue.pull.should == ["myqueue2", message2.to_json]
          queue.pull.should == ["myqueue1", message1.to_json]
        end

        it "returns nil if no queues have messages" do
          queue = Queue.new(connection, "myqueue2", "myqueue1")
          queue.pull.should be_nil
        end

        it "pulls from facets of the queue in a round-robin nature" do
          connection.deliver(message1 = message.merge(facet: 1, topic: "event:1"))
          connection.deliver(message2 = message.merge(facet: 1, topic: "event:1"))
          connection.deliver(message3 = message.merge(facet: 2, topic: "event:1"))
          connection.deliver(message4 = message.merge(facet: 1, topic: "event:2"))

          queue = Queue.new(connection, "myqueue2", "myqueue1")
          queue.pull.should == ["myqueue2", message4.to_json]
          queue.pull.should == ["myqueue1", message1.to_json]
          queue.pull.should == ["myqueue1", message3.to_json]
          queue.pull.should == ["myqueue1", message2.to_json]
        end
      end
    end

    describe "equality" do
      it "should equal queues with same connection and queue names" do
        Queue.new(connection, "a", "b", "c").should == Queue.new(connection, "a", "b", "c")
      end

      it "doesn't equal queues with different connection" do
        new_conn = Connection.new(Fairway.config)
        Queue.new(connection, "a", "b", "c").should_not == Queue.new(new_conn, "a", "b", "c")
      end

      it "doesn't equal queues with different queues" do
        Queue.new(connection, "a", "b", "c").should_not == Queue.new(connection, "a", "b")
      end
    end
  end
end
