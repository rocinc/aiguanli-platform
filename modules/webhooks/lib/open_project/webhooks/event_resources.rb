# frozen_string_literal: true

module OpenProject::Webhooks
  module EventResources
    class << self
      def subscribe!
        resource_modules.each(&:subscribe!)
      end

      ##
      # Return a complete mapping of all resource modules
      # in the form { label => { event1: label , event2: label } }
      def available_events_map
        resource_modules.to_h { |m| [m.resource_name, m.available_events_map] }
      end

      ##
      # Find a module based on the event name
      def lookup_resource_name(event_name)
        resource, events = available_events_map.detect { |_, events_map| events_map.key?(event_name) }
        event = events[event_name] if resource

        [resource, event]
      end

      def resource_modules
        @resource_modules ||= resources.map do |name|
          require_relative "./event_resources/#{name}"
          "OpenProject::Webhooks::EventResources::#{name.to_s.camelize}".constantize
        rescue LoadError, NameError => e
          raise ArgumentError, "Failed to initialize resources module for #{name}: #{e}"
        end
      end

      def resources
        %i(project work_package work_package_comment time_entry attachment)
      end
    end
  end
end
