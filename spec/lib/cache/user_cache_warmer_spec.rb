require "spec_helper"

describe Cache::UserCacheWarmer do

  before(:each) do
    @user_id = rand(99999).to_s
  end

  it "should warm the cache when told" do
    force_cache_write = true
    model_classes = [ User::Api, MyClasses::Merged, Financials::MyFinancials, MyGroups::Merged, MyTasks::Merged, MyActivities::Merged, UpNext::MyUpNext, MyBadges::Merged ]
    model_classes.each do |klass|
      model = klass.new @user_id
      klass.stub(:new).and_return(model)
      klass.stub(:get_feed).and_return({})
      model.should_receive(:get_feed).with(force_cache_write).once
      model.should_receive(:get_feed_as_json).with(force_cache_write).once
    end

    Cache::UserCacheWarmer.do_warm @user_id
  end

end
