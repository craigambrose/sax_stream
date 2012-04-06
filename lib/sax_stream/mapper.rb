require 'sax_stream/internal/field_mapping'
require 'sax_stream/internal/child_mapping'

module SaxStream
  module Mapper
    def self.included(base)
      base.extend ClassMethods
    end

    module ClassMethods
      def node(name)
        @node_name = name
      end

      def map(attribute_name, options)
        mappings[options[:to]] = Internal::FieldMapping.new(attribute_name, options)
      end

      def children(attribute_name, options)
        @child = Internal::ChildMapping.new(attribute_name, options)
      end

      def node_name
        @node_name
      end

      def maps_node?(name)
        @node_name == name
      end

      def map_attribute_onto_object(object, key, value)
        map_key_onto_object(object, "@#{key}", value)
      end

      def map_element_stack_top_onto_object(object, element_stack)
        map_key_onto_object(object, element_stack.path, element_stack.content)
        element_stack.attributes.each do |key, value|
          map_key_onto_object(object, key, value)
        end
      end

      def map_key_onto_object(object, key, value)
        mapping = mappings[key]
        if mapping
          mapping.map_value_onto_object(object, value)
        end
      end

      def child_handler_for(name, collector, handler_stack)
        if @child
          @child.handler_for(name, collector, handler_stack)
        end
      end

      private

        def mappings
          @mappings ||= {}
        end
    end

    def []=(key, value)
      attributes[key] = value
    end

    def [](key)
      attributes[key]
    end

    private

      def attributes
        @attributes ||= {}
      end
  end
end