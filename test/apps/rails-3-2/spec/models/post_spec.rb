require 'spec_helper'

describe Post do
  it "should have an assignable title" do
    title = "A Title"
    title.should == "A Title"
  end
end
