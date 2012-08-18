# require 'kernel'
require 'open3'

class Job < ActiveRecord::Base
  include Ansible

  belongs_to :project
  belongs_to :user
  after_create :execute_task

  default_scope order('created_at DESC')
  default_scope where(:deleted_at => nil)


  def self.deleted
    self.unscoped.where 'deleted_at IS NOT NULL'
  end

  def logger
    @logger ||= Strano::Logger.new(self)
  end

  def read_from(label, stream) while line = stream.gets
      puts "#{label}: #{line}"
    end
  end

  def run_task
    success = true

    ARGV << stage if stage

    puts "Starting run\n"
    puts "chdir #{project.repo.path}\n"
    FileUtils.chdir project.repo.path do
      cmd = %w(bundle exec cap) + full_command.flatten
      puts cmd.join(" ") + "\n"
      out, success = Open3.popen2e(*cmd) do |stdin, stdout_and_stderr, wait_thread|
        puts "Capistrano PID #{wait_thread.pid}\n"
        outerr_reader = Thread.new do
          while bytes = (stdout_and_stderr.readpartial(1024) rescue nil)
            puts bytes
          end
        end
        stdin.close
        [outerr_reader.value, wait_thread.value]
      end

      # out = capture(:stderr) do
      #   success = system("cap #{full_command.join(" ")} >&2")
      #   # success = Strano::CLI.parse(Strano::Logger.new(self), full_command.flatten).execute!
      # end

      if out.is_a?(String)
        puts "\n  \e[33m> #{out}\e" unless out.blank?
      elsif !out.string.blank?
        puts "\n  \e[1;32m> #{out.string}\e"
      end
    end

    !!success
  end

  def complete?
    !completed_at.nil?
  end

  def command
    "#{stage} #{task}"
  end

  def puts(msg)
    update_attribute :results, (results_before_type_cast || '') + msg unless msg.blank?
  end

  def results
    unless (res = read_attribute(:results)).blank?
      escape_to_html res
    end
  end


  private

    def full_command
      %W(-f #{Rails.root.join('Capfile.repos')} -f Capfile -Xx#{verbosity}) + branch_setting + command.split(' ')
    end

    def branch_setting
      %W(-s branch=#{branch}) unless branch.blank?
    end

    def execute_task
      CapExecute.perform_async id
    end

end
