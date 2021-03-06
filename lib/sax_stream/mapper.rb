require 'sax_stream/internal/mapping_factory'
require 'sax_stream/internal/xml_builder'
require 'sax_stream/core_extensions/ordered_hash'
require 'sax_stream/internal/field_mappings'

module SaxStream
  # Include this module to make your class map an XML node. For usage examples, see the READEME.
  module Mapper
    def self.included(base)
      base.extend ClassMethods
    end

    module ClassMethods
      def node(name, options = {})
        @node_name = name
        @collect = options.has_key?(:collect) ? options[:collect] : true
      end

      def map(attribute_name, options = {})
        store_key_for_group attribute_name
        mapping = Internal::MappingFactory.build_mapping(attribute_name, options)
        store_field_mapping(options[:to], mapping)
      end

      def map_all(*params)
        field_mappings.set_map_all(*params)
      end

      def attribute_group(group_name)
        self.mapping_options = {group_name: group_name}
        yield
      ensure
        clear_mapping_options
      end

      # Define a relation to another object which is built from an XML node using another class
      # which also includes SaxStream::Mapper.
      #
      # attribute_name:: The name of the attribute on your object that the related objects will be stored in.
      # options::        An options hash which can accept the following-
      #                    [:to] Default value: "*"
      #                          The path to the XML which defines an instance of this related node. This
      #                          is a bit like an XPath expression, but not quite. See the README for examples.
      #                          For relations, this can include a wildcard "*" as the last part of the path,
      #                          eg: "product/review/*". If the path is just set to "*" then this will match
      #                          any immediate child of the current node, which is good for polymorphic collections.
      #                          You can also specify an array of strings to match against multiple paths, for example,
      #                          to: ['/images/*', 'files/*', 'base_image']
      #                    [:as] Required, no default value.
      #                          Needs to be a class which includes SaxStream::Mapper, or an array of such classes.
      #                          Using an array of classes, even if the array only has one item, denotes that an
      #                          array of related items are expected. Calling @object.relations['name'] will return
      #                          an array which will be empty if nothing is found. If a singular value is used for
      #                          the :as option, then the relation will be assumed to be singular, and so it will
      #                          be nil or the expected class (and will raise an error if multiples are in the file).
      #                    [:parent_collects] Default value: false
      #                          Set to true if the object defining this relationship (ie, the parent
      #                          in the relationship) needs to collect the defined children. If so, the
      #                          parent object will be used as the collector for these children, and they
      #                          will not be passed to the collector supplied to the parser. Use this when
      #                          the child objects are not something you want to process on their own, but
      #                          instead you want them all to be loaded into the parent which will then be
      #                          collected as normal. If this is left false, then the parent ojbect will
      #                          not be informed of it's children, because they will be passed to the collector
      #                          and then forgotten about. However, the children will know about their parent,
      #                          or at least what is known about it, but the parent will not be finished being
      #                          parsed. The parent will have already parsed all XML attributes though.
      def relate(attribute_name, options = {})
        options[:to] ||= '*'
        store_relation_mapping(options[:to], Internal::MappingFactory.build_relation(attribute_name, options))
      end

      def node_name
        @node_name
      end

      def maps_node?(name)
        @node_name == name || @node_name == '*'
      end

      def map_attribute_onto_object(object, key, value)
        map_key_onto_object(object, "@#{key}", value)
      end

      def map_element_stack_top_onto_object(object, element_stack)
        map_key_onto_object(object, element_stack.path, element_stack.content, element_stack.relative_attributes)
        element_stack.attributes.each do |key, value|
          map_key_onto_object(object, key, value)
        end
      end

      def map_key_onto_object(object, key, value, attributes = [])
        if value
          mapping = field_mapping(key, attributes)
          if mapping
            mapping.map_value_onto_object(object, key, value)
          end
        end
      end

      def child_handler_for(key, attributes, collector, handler_stack, current_object)
        mapping = field_mapping(key, attributes)
        if mapping
          mapping.handler_for(key, collector, handler_stack, current_object)
        end
      end

      def relation_mappings
        (class_relation_mappings + parent_class_values(:relation_mappings, [])).freeze
      end

      def mappings
        @mappings_incuding_inherited ||= parent_class_values(:mappings, CoreExtensions::OrderedHash.new).merge(class_mappings).freeze
      end

      def should_collect?
        @collect
      end

      def group_keys(group_name)
        @group_keys ||= {}
        @group_keys[group_name] ||= []
      end

      def field_mapping(key, attributes = [])
        field_mappings.field_mapping(key, attributes) || parent_field_mapping(key, attributes)
      end

      private

        def class_mappings
          field_mappings.class_mappings
        end

        def store_relation_mapping(key, mapping)
          class_relation_mappings << mapping
          store_field_mapping(key, mapping)
        end

        def store_field_mapping(key, mapping)
          field_mappings.store(key, mapping)
        end

        def field_mappings
          @field_mappings ||= Internal::FieldMappings.new
        end

        def parent_field_mapping(*params)
          parent_class_values :field_mapping, nil, *params
        end

        def class_relation_mappings
          @relation_mappings ||= []
        end

        def parent_class_values(method_name, default = nil, *params)
          superclass && superclass.respond_to?(method_name) ? superclass.send(method_name, *params) : default
        end

        def mapping_options=(values)
          @mapping_options = values
        end

        def clear_mapping_options
          @mapping_options = nil
        end

        def with_mapping_options(input)
          @mapping_options ? input.merge(@mapping_options) : input
        end

        def store_key_for_group(key)
          group_name = (@mapping_options || {})[:group_name]
          if group_name
            self.group_keys(group_name) << key
          end
        end
    end

    def []=(key, value)
      attributes[key] = value
    end

    def [](key)
      attributes[key]
    end

    def inspect
      "#{self.class.name}: #{attributes.inspect}"
    end

    def attributes
      @attributes ||= {}
    end

    def attributes=(value)
      @attributes = value
    end

    def group_attributes(group_name)
      keys = self.class.group_keys(group_name).map(&:to_s)
      attributes.reject {|key, value| !keys.include?(key) }
    end

    def relations
      @relations ||= build_empty_relations
    end

    def mappings
      self.class.mappings.values
    end

    def node_name
      @node_name || self.class.node_name
    end

    def node_name=(value)
      @node_name = value
    end

    def should_collect?
      self.class.should_collect?
    end

    def to_xml(encoding = 'UTF-8', builder = nil)
      builder ||= Internal::XmlBuilder.new(:encoding => encoding)
      builder.build_xml_for(self)
    end

    private

      def build_empty_relations
        result = {}
        self.class.relation_mappings.each do |relation_mapping|
          result[relation_mapping.name] = relation_mapping.build_empty_relation
        end
        result
      end

  end
end