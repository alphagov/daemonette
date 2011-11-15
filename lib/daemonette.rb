require "tmpdir"

# Daemonise a block, supplanting any previous incarnation
#
class Daemonette
  WAIT_HUP    = 20   # Seconds to wait after HUP before KILL
  WAIT_KILL   = 20   # Seconds to wait after KILL before giving up
  GRANULARITY =  0.2 # Seconds to sleep whilst waiting for a state change

  # Run the task defined in &blk as a daemonised process.
  # name defines the pid file used.
  # If another process is already running, it will be killed, first gently,
  # then with extreme prejudice.
  #
  def self.run(name, &blk)
    new(name).run(&blk)
  end

  attr_reader :name

  def initialize(name)
    @name = name
  end

  def run(&blk)
    forked_pid = fork {
      begin
        kill_antecedent
        Process.daemon(true)
        write_pid Process.pid
        yield
      rescue Exception => e
        File.open("#{name}.daemonette-dump", "w") do |f|
          f.puts e.class, e, *e.backtrace
        end
        raise e
      end
    }
    Process.detach forked_pid if forked_pid
  end

private
  def pid_file
    File.join(Dir.tmpdir, name) + ".pid"
  end

  def write_pid(pid)
    File.open(pid_file, "w") do |f|
      f.puts Process.pid
    end
  end

  def pid_of_antecedent
    if File.exist?(pid_file)
      File.read(pid_file)[/\d+/].to_i
    else
      nil
    end
  end

  def running?(pid)
    pids = `ps -A | awk '{print $1}'`.scan(/\d+/).map(&:to_i)
    pids.include?(pid)
  end

  def kill_antecedent
    pid = pid_of_antecedent
    return unless pid && running?(pid)
    kill pid, "HUP",  WAIT_HUP or
    kill pid, "KILL", WAIT_KILL or
    raise "Couldn't kill process #{pid}"
  end

  def kill(pid, signal, time_to_wait)
    cutoff = Time.now + time_to_wait
    Process.kill signal, pid
    while running?(pid) && Time.now < cutoff
      sleep GRANULARITY
    end
    !running?(pid)
  end
end
