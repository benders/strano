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

    log highlight("> cd #{project.repo.path}")
    FileUtils.chdir project.repo.path do
      bundled = run_command("bundle check || bundle install --deployment --without 'development test'")
      return false unless bundled

      cmd = %w(bundle exec cap) + full_command.flatten
      success = run_command(*cmd)
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

  def read_thread(stream)
    Thread.new {
      while bytes = (stream.readpartial(1024) rescue nil)
        yield(bytes)
      end
    }
  end

  def highlight(string)
    "\e[#{33}m" + string + "\e[0m"
  end

  def run_command(*cmd)
    log highlight("> " + [*cmd].join(' '))
    Bundler.with_clean_env do
      Open3.popen2e(*cmd) do |stdin, outerr, wait_thread|
        stdin.close
        out_reader = read_thread(outerr) { |bytes| log_raw(bytes) }
        wait_thread.value
      end
    end
  end
end
