require "spec_helper"

module Fairway::Sidekiq
  describe Fetch do
    describe "#initialize" do
      it "accepts a block to define of fetches with priority" do
        fetch = Fetch.new do |fetch|
          fetch.from :fetchA, 10
          fetch.from :fetchB, 1
        end

        fetch.fetches.should == [Array.new(10, :fetchA), :fetchB].flatten
      end

      it "instantiates a BasicFetch if you fetch from the keyword :sidekiq" do
        fetch = Fetch.new do |fetch|
          fetch.from :sidekiq, 1
        end

        fetch.fetches.length.should == 1
        fetch.fetches.first.should be_instance_of(BasicFetch)
      end
    end

    describe "#new" do
      it "returns itself to match Sidekiq fetch API" do
        fetch = Fetch.new do |fetch|
          fetch.from :fetchA, 1
        end

        fetch.new.should == fetch
      end
    end

    describe "#fetch_order" do
      let(:fetch)  { Fetch.new { |f| f.from :fetchA, 10; f.from :fetchB, 1 } }

      it "should shuffle and uniq fetches" do
        fetch.fetches.should_receive(:shuffle).and_return(fetch.fetches)
        fetch.fetch_order
      end

      it "should unique fetches list" do
        fetch.fetches.length.should == 11
        fetch.fetch_order.length.should == 2
      end
    end

    describe "#retrieve_work" do
      let(:work)   { mock(:work)  }
      let(:fetchA) { mock(:fetch) }
      let(:fetchB) { mock(:fetch) }
      let(:fetch)  { Fetch.new { |f| f.from :fetchA, 10; f.from :fetchB, 1 } }

      before do
        fetch.stub(fetch_order: [fetchA, fetchB], sleep: nil)
      end

      it "returns work from the first fetch who has work" do
        fetchA.stub(retrieve_work: work)
        fetchB.should_not_receive(:retrieve_work)

        fetch.retrieve_work.should == work
      end

      it "attempts to retrieve work from each fetch in a non blocking fashion" do
        fetchA.should_receive(:retrieve_work).with(blocking: false)
        fetchB.should_receive(:retrieve_work).with(blocking: false)
        fetch.retrieve_work.should be_nil
      end

      it "sleeps if no work is found" do
        fetch.should_receive(:sleep).with(1)

        fetchA.stub(retrieve_work: nil)
        fetchB.stub(retrieve_work: nil)

        fetch.retrieve_work
      end
    end
  end
end
