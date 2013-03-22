describe :thread_wakeup, :shared => true do
  it "can interrupt Kernel#sleep" do
    exit_loop = false
    after_sleep1 = false
    after_sleep2 = false

    t = Thread.new do
      while true
        break if exit_loop == true
      end

      sleep
      after_sleep1 = true

      sleep
      after_sleep2 = true
    end

    10.times { t.send(@method); Thread.pass }
    t.status.should_not == "sleep"

    exit_loop = true

    Thread.pass while t.status and t.status != "sleep"
    after_sleep1.should == false # t should be blocked on the first sleep
    t.send(@method)

    Thread.pass while after_sleep1 != true
    Thread.pass while t.status and t.status != "sleep"
    after_sleep2.should == false # t should be blocked on the second sleep
    t.send(@method)

    t.join
  end

  it "does not result in a deadlock" do
    t = Thread.new do
      1000.times {Thread.stop }
    end

    while(t.status != false) do
      begin
        t.send(@method)
      rescue ThreadError
        # The thread might die right after.
        t.status.should == false
      end
      Thread.pass
    end

    1.should == 1 # test succeeds if we reach here
  end

  it "raises a ThreadError when trying to wake up a dead thread" do
    t = Thread.new { 1 }
    t.join
    lambda { t.wakeup }.should raise_error(ThreadError)
  end
end
