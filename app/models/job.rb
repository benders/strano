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

  def run_task
    success = true

    ARGV << stage if stage

    log "\e[33m> Starting run\e[0m"
    log "chdir #{project.repo.path}"
    FileUtils.chdir project.repo.path do
      cmd = %w(bundle exec cap) + full_command.flatten
      log cmd.inspect
      success = Open3.popen2e(*cmd) do |stdin, stdout_and_stderr, wait_thread|
        log "Capistrano PID #{wait_thread.pid}"
        outerr_reader = Thread.new do
          while bytes = (stdout_and_stderr.readpartial(1024) rescue nil)
            log_raw bytes
          end
        end
        stdin.close
        wait_thread.value
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

  def log(msg)
    log_raw(msg + "\n")
  end

  def log_raw(msg)
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
