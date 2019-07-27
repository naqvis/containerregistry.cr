require "logger"

module V1::Logger
  @@log = ::Logger.new(STDOUT, progname: "containerregistry")
  @@log.level = ::Logger::DEBUG
  @@log.formatter = ::Logger::Formatter.new do |severity, datetime, progname, message, io|
    label = severity.unknown? ? "ANY" : severity.to_s
    io << "[" << datetime << " #" << Process.pid << "] "
    io << label.rjust(5) << " -- " << progname << ": " << message
  end

  def self.info(msg)
    @@log.info(msg)
  end

  def self.debug(msg)
    @@log.debug(msg)
  end

  def self.warn(msg)
    @@log.warn(msg)
  end

  def self.fatal(msg)
    @@log.fatal(msg)
  end

  def self.error(msg)
    @@log.error(msg)
  end
end
