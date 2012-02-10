require 'memcache'
require 'activemessaging/adapters/base'

module ActiveMessaging
  module Adapters
    # This module contains code to integrate the ActiveMessaging framework with a
    # kestrel message queue server.
    module Kestrel
      QUEUE_NAME_NORMALIZATIONS = {
        '/' => '__4S__',
        '.' => '__D0T__',
        '~' => '__T1L__'
      }
      # Simple struct for wrapping received messages
      Message = Struct.new(:headers, :body, :destination) do
        def matches_subscription?(subscription)
          destination.to_s == subscription.destination.value.to_s
        end
      end

      # Resolve the provided string into a class object
      def to_class(class_name, initial_scope = Kernel)
        class_name.split('::').inject(initial_scope) { |scope, const_name| scope.const_get(const_name) }
      end

      # class for retrying things (should be pulled into a separate gem)
      class SimpleRetry
        # Yields to caller's block and retries up to options[:tries] (default 3)
        # times in the face of exceptions.  Returns return result of block if
        # successful.  If number of tries is exhausted, the exception is reraised.
        # Retry loop will sleep options[:delay] seconds between retries (default 5).
        # If you want error logging, pass in :logger.  If not provided, ActiveMessaging.logger
        # is used if defined.
        def do_work(options = {})
          use_options = {:tries => 3, :delay => 5}.merge(options || {})
          exception = nil
          return_value = nil
          logger = use_options[:logger] || (defined?(::ActiveMessaging) ? ::ActiveMessaging.logger : nil)
          use_options[:tries].times do |try|
            begin
              exception = nil
              return_value = yield
              break
            rescue Exception => e
              exception = e
              logger.warn("Got error on try #{try}: #{exception} retrying after #{use_options[:delay]} seconds") if logger
            end
            sleep use_options[:delay]
          end

          raise exception if exception
          return return_value
        end
      end

      # Connection to a kestrel message queue server
      class Connection < ActiveMessaging::Adapters::BaseConnection
        include ActiveMessaging::Adapter
        register :kestrel
        # Reconnect on error
        attr_accessor :retry_policy
        # Logging
        attr_accessor :logger

        KESTREL_STATS_QUEUE_KEYS = [:items, :bytes, :total_items, :logsize, :expired_items, :mem_items, :mem_bytes, :age, :discarded, :waiters, :open_transactions] unless defined?(KESTREL_STATS_QUEUE_KEYS)

        # Create a new Kestrel adapter using the provided config
        def initialize(cfg = {})
          # Like symbol keys
          cfg = symbolize_keys(cfg)

          # Create a logger.  Use framework loggers when available.
          @logger = cfg.delete(:logger) || ActiveMessaging.logger || (defined?(::Rails) && ::Rails.logger ? ::Rails.logger : nil) || default_logger

          # Get the retry policy
          @retry_policy = cfg.delete(:retry_policy) || {:strategy => SimpleRetry, :config => {:tries => 1, :delay => 5}}
          # If the retry policy came from the cfg, make sure we set the :logger
          @retry_policy[:config][:logger] ||= @logger
          # Turn the strategy into a Class if it is a String
          if @retry_policy[:strategy].is_a?(String)
            # Convert strategy from string to class
            @retry_policy[:strategy] = Kestrel.const_get(@retry_policy[:strategy]) rescue Kestrel.to_class(@retry_policy[:strategy])
          end

          @empty_queues_delay = cfg.delete(:empty_queues_delay)
          @config = cfg
          @subscriptions = {}
          retrier
          connect
          nil
        end

        # Returns hash of hashes of hashes containing stats for each active queue
        # in each member of the kestrel cluster.
        # top level hash has following structure:
        #  { "server1_def" => { "queue1" => { ... }, "queue2" => { ... } },
        #    "server2_def" => { "queue1" => { ... }, "queue2" => { ... } } }
        # "server_def" are host:port
        def queue_stats
          stats = @kestrel.stats
          queues = stats.values.inject([]) do |queue_names, hash|
            hash.keys.each do |key|
              if md = /queue_(.+)_total_items/.match(key)
                queue_names << md[1]
              end
            end
            queue_names
          end
          stats.inject(Hash.new{|h,k| h[k] = Hash.new(&h.default_proc) }) do |return_hash, (server_def, stats_hash)|
            queues.each do |queue|
              KESTREL_STATS_QUEUE_KEYS.each do |key|
                stats_key = "queue_#{queue}_#{key}"
                denormalized_name = queue.gsub('FS', '/') # denormalize the name ...
                return_hash[server_def][denormalized_name][key] = stats_hash[stats_key]
              end
            end
            return_hash
          end
        end

        # Connect to the kestrel server using a Memcached client
        def connect
          logger.debug("Creating connection to Kestrel using config #{@config.inspect}") if logger && logger.level <= Logger::DEBUG
          @kestrel = MemCache.new(@config)
          @kestrel.servers = @config[:servers]
        end

        # Creates a retrier object according to the @retry_policy
        def retrier
          @retrier ||= begin
            @retry_policy[:strategy].new
          end
        end
 
        # Subscribe to the named destination and begin receiving
        # messages from it
        def subscribe(destination_name, headers = {})
          headers[:destination] = destination_name
          if @subscriptions[destination_name]
            # TODO: Should you get an exception or no?
          else
            @subscriptions[destination_name] = headers
          end
          nil
        end

        # Stop receiving messages from the named destination
        def unsubscribe(destination_name, headers = {})
          @subscriptions.delete(destination_name)
        end

        # Send a message to the named destination.  headers can
        # include any of the following keys:
        #    :ttl => Set the time to live of the message in seconds
        def send(destination_name, body, headers = {})
          ttl = (headers[:ttl] || 0).to_i
          if ttl <= 0
            @kestrel.set(normalize(destination_name), body)
          else
            @kestrel.set(normalize(destination_name), body, ttl)
          end
        end

        # Gets a message from any subscribed destination and returns it as a 
        # ActiveMessaging::Adaptors::Kestrel::Message object
        def receive

          if @subscriptions.size > 0
            @retrier.do_work(@retry_policy[:config]) do
              queues_to_check = @subscriptions.size > 1 ? @subscriptions.keys.sort_by{rand} : @subscriptions.keys
              queues_to_check.each do |queue|
                if item = @kestrel.get(normalize(queue))
                  # TODO: ActiveMessaging ought to provide a way to do messaging
                  # without having to wrap the messages in another object
                  #logger.debug("Got message from queue #{queue}: #{item}") if logger.level <= Logger::DEBUG
                  return Message.new({'destination' => queue}, item, queue)
                end
              end
            end
          end
          # Sleep a little to avoid a spin loop (ActiveMessaging Gateway ought to do this)
          sleep(@empty_queues_delay) if @empty_queues_delay && @empty_queues_delay > 0
          return nil
        end

        private
          def default_logger
            # Create a logger on STDOUT at debug level
            logger = Logger.new(STDOUT)
            logger.level = Logger::DEBUG
            logger
          end

          def denormalize(name)
            @denormalized_names ||= Hash.new do |h,k|
              newkey = k
              QUEUE_NAME_NORMALIZATIONS.each do |bad, good|
                newkey = newkey.gsub(good, bad)
              end
              h[k] = newkey
            end
            @denormalized_names[name]
          end

          def normalize(name)
            # Kestrel doesn't like certain chars in queue names, so get rid of them
            # (and memoize the calculation)
            @normalized_names ||= Hash.new do |h,k|
              newkey = k
              QUEUE_NAME_NORMALIZATIONS.each do |bad, good|
                newkey = newkey.gsub(bad, good)
              end
              h[k] = newkey
            end
            @normalized_names[name]
          end

          def symbolize_keys(hash)
            hash.inject({}) do |new_hash, (k, v)|
              if v.is_a?(Hash)
                v = symbolize_keys(v)
              end
              new_hash[k.to_sym] = v
              new_hash
            end
          end
      end
    end
  end
end
