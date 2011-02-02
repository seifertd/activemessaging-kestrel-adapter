require 'memcache'
require 'activemessaging/adapters/base'

module ActiveMessaging
  module Adapters
    # This module contains code to integrate the ActiveMessaging framework with a
    # kestrel message queue server.
    module Kestrel
      # Simple struct for wrapping received messages
      Message = Struct.new(:headers, :body, :command)

      # Connection to a kestrel message queue server
      class Connection < ActiveMessaging::Adapters::Base::Connection
        include ActiveMessaging::Adapter
        register :kestrel
        attr_accessor :reliable
        # Time to sleep between polls of empty queues
        attr_accessor :receive_throttle
        # Reconnect on error
        attr_accessor :error_policy

        def initialize(cfg)
          @receive_throttle = cfg.delete(:receive_throttle) || 0.1
          # TODO: Implement error policies
          @error_policy = cfg.delete(:error_policy) || :reconnect
          @config = cfg
          @queues = {}
          connect
          nil
        end

        # Connect to the kestrel server using a Memcached client
        def connect
          @kestrel = MemCache.new(@config)
          @kestrel.servers = @config[:servers]
        end
 
        # Subscribe to the named destination and begin receiving
        # messages from it
        def subscribe(destination_name, headers = {})
          headers[:destination] = destination_name
          if @queues[destination_name]
            # TODO: Should you get an exception or no?
          else
            @queues[destination_name] = headers
          end
          nil
        end

        # Stop receiving messages from the named destination
        def unsubscribe(destination_name, headers = {})
          @queues.delete(destination_name)
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
          # TODO: Is this what ActiveMessaging expects: can it handle a nil return?
          #while (true)
            # Get a message from a subscribed queue, but don't favor any queue over another
            queues_to_check = @queues.size > 1 ? @queues.keys.sort_by{rand} : @queues.keys
            queues_to_check.each do |queue|
              if item = @kestrel.get(normalize(queue))
                # TODO: ActiveMessaging ought to provide a way to do messaging
                # without having to wrap the messages in another object
                return Message.new({'destination' => queue}, item, 'MESSAGE')
              end
            end
          #  # Sleep a bit so we don't get into a spinloop
          #  sleep @receive_throttle
          #end
          return nil
        end

        private
          def normalize(name)
            # Kestrel doesn't like '/' chars in queue names, so get rid of them
            # (and memoize the calculation)
            @normalized_names ||= Hash.new {|h,k| h[k] = k.gsub('/', '--FS--')}
            @normalized_names[name]
          end
      end
    end
  end
end
