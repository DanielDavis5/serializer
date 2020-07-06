require "semantic_version"
require "uuid"

require "json"
require "yaml"

require "./annotations"
require "./any"
require "./context"
require "./serializer_interface"
require "./serializer"
require "./property_metadata"
require "./deserialization_context"
require "./serialization_context"

require "./construction/*"
require "./exclusion_strategies/*"
require "./navigators/*"
require "./visitors/*"

# Convenience alias to make referencing `Athena::Serializer` types easier.
alias ASR = Athena::Serializer

# Convenience alias to make referencing `Athena::Serializer::Annotations` types easier.
alias ASRA = Athena::Serializer::Annotations

# :nodoc:
module JSON; end

# :nodoc:
module YAML; end

# Athena's Serializer component, `ASR` for short, adds enhanced (de)serialization features to your project.
#
# ## Getting Started
#
# The serializer component utilizes a module to specify that a type is serializable, as well as annotations to control how it gets (de)serialized.
#
# ### Installation
#
# Add the dependency to your `shard.yml`:
#
# ```yaml
# dependencies:
#   athena-serializer:
#     github: athena-framework/serializer
#     version: ~> 0.1.0
# ```
#
# Run `shards install`.
#
# ### Usage
#
# See the `ASR::Annotations` namespace a complete list of annotations, as well as each annotation for more detailed information.
#
# ```
# # ExclusionPolicy specifies that all properties should not be (de)serialized
# # unless exposed via the `ASRA::Expose` annotation.
# @[ASRA::ExclusionPolicy(:all)]
# @[ASRA::AccessorOrder(:alphabetical)]
# class Example
#   include ASR::Serializable
#
#   # Groups can be used to create different "views" of a type.
#   @[ASRA::Expose]
#   @[ASRA::Groups("details")]
#   property name : String
#
#   # The `ASRA::Name` controls the name that this property
#   # should be deserialized from or be serialized to.
#   # It can also be used to set the default serialized naming strategy on the type.
#   @[ASRA::Expose]
#   @[ASRA::Name(deserialize: "a_prop", serialize: "a_prop")]
#   property some_prop : String
#
#   # Define a custom accessor used to get the value for serialization.
#   @[ASRA::Expose]
#   @[ASRA::Groups("default", "details")]
#   @[ASRA::Accessor(getter: get_title)]
#   property title : String
#
#   # ReadOnly properties cannot be set on deserialization
#   @[ASRA::Expose]
#   @[ASRA::ReadOnly]
#   property created_at : Time = Time.utc
#
#   # Allows the property to be set via deserialization,
#   # but not exposed when serialized.
#   @[ASRA::IgnoreOnSerialize]
#   property password : String?
#
#   # Because of the `:all` exclusion policy, and not having the `ASRA::Expose` annotation,
#   # these properties are not exposed.
#   getter first_name : String?
#   getter last_name : String?
#
#   # Runs directly after `self` is deserialized
#   @[ASRA::PostDeserialize]
#   def split_name : Nil
#     @first_name, @last_name = @name.split(' ')
#   end
#
#   # Allows using the return value of a method as a key/value in the serialized output.
#   @[ASRA::VirtualProperty]
#   def get_val : String
#     "VAL"
#   end
#
#   private def get_title : String
#     @title.downcase
#   end
# end
#
# obj = ASR.serializer.deserialize Example, %({"name":"FIRST LAST","a_prop":"STR","title":"TITLE","password":"monkey123","created_at":"2020-10-10T12:34:56Z"}), :json
# obj                                                                                     # => #<Example:0x7f3e3b106740 @created_at=2020-07-05 23:06:58.943298289 UTC, @name="FIRST LAST", @some_prop="STR", @title="TITLE", @password="monkey123", @first_name="FIRST", @last_name="LAST">
# ASR.serializer.serialize obj, :json                                                     # => {"a_prop":"STR","created_at":"2020-07-05T23:06:58.94Z","get_val":"VAL","name":"FIRST LAST","title":"title"}
# ASR.serializer.serialize obj, :json, ASR::SerializationContext.new.groups = ["details"] # => {"name":"FIRST LAST","title":"title"}
# ```
module Athena::Serializer
  # Returns an `ASR::SerializerInterface` instance for ad-hoc (de)serialization.
  #
  # The serializer is cached and only instantiated once.
  class_getter serializer : ASR::SerializerInterface { ASR::Serializer.new }

  # The built-in supported formats.
  enum Format
    JSON
    YAML

    # Returns the `ASR::Visitors::SerializationVisitorInterface` related to `self`.
    def serialization_visitor
      case self
      in .json? then ASR::Visitors::JSONSerializationVisitor
      in .yaml? then ASR::Visitors::YAMLSerializationVisitor
      end
    end

    # Returns the `ASR::Visitors::DeserializationVisitorInterface` related to `self`.
    def deserialization_visitor
      case self
      in .json? then ASR::Visitors::JSONDeserializationVisitor
      in .yaml? then ASR::Visitors::YAMLDeserializationVisitor
      end
    end
  end

  # Exclusion Strategies allow controlling which properties should be (de)serialized.
  #
  # `Athena::Serializer` includes two common strategies: `ASR::ExclusionStrategies::Groups`, and `ASR::ExclusionStrategies::Version`.
  #
  # Custom strategies can be implemented by via `ExclusionStrategies::ExclusionStrategyInterface`.
  #
  # OPTIMIZE:  Once feasible, support compile time exclusion strategies.
  module Athena::Serializer::ExclusionStrategies; end

  # Used to denote a type that is (de)serializable.
  #
  # This module can be used to make the compiler happy in some situations, it doesn't do anything on its own.
  # You most likely want to use `ASR::Serializable` instead.
  #
  # ```
  # require "athena-serializer"
  #
  # abstract struct BaseModel
  #   # `ASR::Model` is needed here to ensure typings are correct for the deserialization process.
  #   # Child types should still include `ASR::Serializable`.
  #   include ASR::Model
  # end
  #
  # record ModelOne < BaseModel, id : Int32, name : String do
  #   include ASR::Serializable
  # end
  #
  # record ModelTwo < BaseModel, id : Int32, name : String do
  #   include ASR::Serializable
  # end
  #
  # record Unionable, type : BaseModel.class
  # ```
  module Athena::Serializer::Model; end

  # Adds the necessary methods to a `struct`/`class` to allow for (de)serialization of that type.
  #
  # ```
  # require "athena-serializer"
  #
  # record Example, id : Int32, name : String do
  #   include ASR::Serializable
  # end
  #
  # obj = ASR.serializer.deserialize Example, %({"id":1,"name":"George"}), :json
  # obj                                 # => Example(@id=1, @name="George")
  # ASR.serializer.serialize obj, :yaml # =>
  # # ---
  # # id: 1
  # # name: George
  # ```
  module Serializable
    # :nodoc:
    abstract def serialization_properties : Array(ASR::PropertyMetadataBase)

    # :nodoc:
    abstract def run_preserialize : Nil

    # :nodoc:
    abstract def run_postserialize : Nil

    # :nodoc:
    abstract def run_postdeserialize : Nil

    macro included
      {% verbatim do %}
        include ASR::Model

        # :nodoc:
        def run_preserialize : Nil
          {% for method in @type.methods.select { |m| m.annotation(ASRA::PreSerialize) } %}
            {{method.name}}
          {% end %}
        end

        # :nodoc:
        def run_postserialize : Nil
          {% for method in @type.methods.select { |m| m.annotation(ASRA::PostSerialize) } %}
            {{method.name}}
          {% end %}
        end

        # :nodoc:
        def run_postdeserialize : Nil
          {% for method in @type.methods.select { |m| m.annotation(ASRA::PostDeserialize) } %}
            {{method.name}}
          {% end %}
        end

        # :nodoc:
        def serialization_properties : Array(ASR::PropertyMetadataBase)
          {% begin %}
            # Construct the array of metadata from the properties on `self`.
            # Takes into consideration some annotations to control how/when a property should be serialized
            {%
              instance_vars = @type.instance_vars
                .reject { |ivar| ivar.annotation(ASRA::Skip) }
                .reject { |ivar| ivar.annotation(ASRA::IgnoreOnSerialize) }
                .reject do |ivar|
                  not_exposed = (ann = @type.annotation(ASRA::ExclusionPolicy)) && ann[0] == :all && !ivar.annotation(ASRA::Expose)
                  excluded = (ann = @type.annotation(ASRA::ExclusionPolicy)) && ann[0] == :none && ivar.annotation(ASRA::Exclude)

                  !ivar.annotation(ASRA::IgnoreOnDeserialize) && (not_exposed || excluded)
                end
            %}

            {% property_hash = {} of Nil => Nil %}

            {% for ivar in instance_vars %}
              {% ivar_name = ivar.name.stringify %}

              # Determine the serialized name of the ivar:
              # 1. If the ivar has an `ASRA::Name` annotation with a `serialize` field, use that
              # 2. If the type has an `ASRA::Name` annotation with a `strategy`, use that strategy
              # 3. Fallback on the name of the ivar
              {% external_name = if (name_ann = ivar.annotation(ASRA::Name)) && (serialized_name = name_ann[:serialize])
                                   serialized_name
                                 elsif (name_ann = @type.annotation(ASRA::Name)) && (strategy = name_ann[:strategy])
                                   if strategy == :camelcase
                                     ivar_name.camelcase lower: true
                                   elsif strategy == :underscore
                                     ivar_name.underscore
                                   elsif strategy == :identical
                                     ivar_name
                                   else
                                     strategy.raise "Invalid ASRA::Name strategy: '#{strategy}'."
                                   end
                                 else
                                   ivar_name
                                 end %}

              {% property_hash[external_name] = %(ASR::PropertyMetadata(#{ivar.type}, #{ivar.type}, #{@type}).new(
                  name: #{ivar.name.stringify},
                  external_name: #{external_name},
                  value: #{(accessor = ivar.annotation(ASRA::Accessor)) && accessor[:getter] != nil ? accessor[:getter].id : %(@#{ivar.id}).id},
                  skip_when_empty: #{!!ivar.annotation(ASRA::SkipWhenEmpty)},
                  groups: #{(ann = ivar.annotation(ASRA::Groups)) && !ann.args.empty? ? [ann.args.splat] : ["default"]},
                  since_version: #{(ann = ivar.annotation(ASRA::Since)) && !ann[0].nil? ? "SemanticVersion.parse(#{ann[0]})".id : nil},
                  until_version: #{(ann = ivar.annotation(ASRA::Until)) && !ann[0].nil? ? "SemanticVersion.parse(#{ann[0]})".id : nil},
                )).id %}
              {% end %}

            {% for m in @type.methods.select { |method| method.annotation(ASRA::VirtualProperty) } %}
              {% method_name = m.name %}
              {% m.raise "ASRA::VirtualProperty return type must be set for '#{@type.name}##{method_name}'." if m.return_type.is_a? Nop %}
              {% external_name = (ann = m.annotation(ASRA::Name)) && (name = ann[:serialize]) ? name : m.name.stringify %}

              {% property_hash[external_name] = %(ASR::PropertyMetadata(#{m.return_type}, #{m.return_type}, #{@type}).new(
                  name: #{m.name.stringify},
                  external_name: #{external_name},
                  value: #{m.name.id},
                  skip_when_empty: #{!!m.annotation(ASRA::SkipWhenEmpty)},
                )).id %}
            {% end %}

            {% if (ann = @type.annotation(ASRA::AccessorOrder)) && !ann[0].nil? %}
              {% if ann[0] == :alphabetical %}
                {% properties = property_hash.keys.sort.map { |key| property_hash[key] } %}
              {% elsif ann[0] == :custom && !ann[:order].nil? %}
                {% ann.raise "Not all properties were defined in the custom order for '#{@type}'." unless property_hash.keys.all? { |prop| ann[:order].map(&.id.stringify).includes? prop } %}
                {% properties = ann[:order].map { |val| property_hash[val.id.stringify] || raise "Unknown instance variable: '#{val.id}'." } %}
              {% else %}
                {% ann.raise "Invalid ASR::AccessorOrder value: '#{ann[0].id}'." %}
              {% end %}
            {% else %}
              {% properties = property_hash.values %}
            {% end %}

            {{properties}} of ASR::PropertyMetadataBase
          {% end %}
        end

        # :nodoc:
        def self.deserialization_properties : Array(ASR::PropertyMetadataBase)
          {% verbatim do %}
            {% begin %}
              # Construct the array of metadata from the properties on `self`.
              # Takes into consideration some annotations to control how/when a property should be serialized
              {% instance_vars = @type.instance_vars
                   .reject { |ivar| ivar.annotation(ASRA::Skip) }
                   .reject { |ivar| (ann = ivar.annotation(ASRA::ReadOnly)); ann && !ivar.has_default_value? && !ivar.type.nilable? ? ivar.raise "#{@type}##{ivar.name} is read-only but is not nilable nor has a default value" : ann }
                   .reject { |ivar| ivar.annotation(ASRA::IgnoreOnDeserialize) }
                   .reject do |ivar|
                     not_exposed = (ann = @type.annotation(ASRA::ExclusionPolicy)) && ann[0] == :all && !ivar.annotation(ASRA::Expose)
                     excluded = (ann = @type.annotation(ASRA::ExclusionPolicy)) && ann[0] == :none && ivar.annotation(ASRA::Exclude)

                     !ivar.annotation(ASRA::IgnoreOnSerialize) && (not_exposed || excluded)
                   end %}

              {{instance_vars.map do |ivar|
                  %(ASR::PropertyMetadata(#{ivar.type}, #{ivar.type}?, #{@type}).new(
                    name: #{ivar.name.stringify},
                    external_name: #{(ann = ivar.annotation(ASRA::Name)) && (name = ann[:deserialize]) ? name : ivar.name.stringify},
                    aliases: #{(ann = ivar.annotation(ASRA::Name)) && (aliases = ann[:aliases]) ? aliases : "[] of String".id},
                    groups: #{(ann = ivar.annotation(ASRA::Groups)) && !ann.args.empty? ? [ann.args.splat] : ["default"]},
                    since_version: #{(ann = ivar.annotation(ASRA::Since)) && !ann[0].nil? ? "SemanticVersion.parse(#{ann[0]})".id : nil},
                    until_version: #{(ann = ivar.annotation(ASRA::Until)) && !ann[0].nil? ? "SemanticVersion.parse(#{ann[0]})".id : nil},
                  )).id
                end}} of ASR::PropertyMetadataBase
            {% end %}
          {% end %}
        end

        # :nodoc:
        def apply(navigator : ASR::Navigators::DeserializationNavigator, properties : Array(ASR::PropertyMetadataBase), data : ASR::Any)
          self.initialize navigator, properties, data
        end

        # :nodoc:
        def initialize(navigator : ASR::Navigators::DeserializationNavigatorInterface, properties : Array(ASR::PropertyMetadataBase), data : ASR::Any)
          {% begin %}
            {% for ivar, idx in @type.instance_vars %}
              if (prop = properties.find { |p| p.name == {{ivar.name.stringify}} }) && (val = extract_value(prop, data, {{(ann = ivar.annotation(ASRA::Accessor)) ? ann[:path] : nil}}))
                value = {% if (ann = ivar.annotation(ASRA::Accessor)) && (converter = ann[:converter]) %}
                          {{converter.id}}.deserialize navigator, prop, val
                        {% else %}
                          navigator.accept {{ivar.type}}, val
                        {% end %}

                unless value.nil?
                  @{{ivar.id}} = value
                else
                  {% if !ivar.type.nilable? && !ivar.has_default_value? %}
                    raise Exception.new "Required property '{{ivar}}' cannot be nil."
                  {% end %}
                end
              else
                {% if !ivar.type.nilable? && !ivar.has_default_value? %}
                  raise Exception.new "Missing required attribute: '{{ivar}}'."
                {% end %}
              end

              {% if (ann = ivar.annotation(ASRA::Accessor)) && (setter = ann[:setter]) %}
                self.{{setter.id}}(@{{ivar.id}})
              {% end %}
            {% end %}
          {% end %}
        end

        # Attempts to extract a value from the *data* for the given *property*.
        # Returns `nil` if a value could not be extracted.
        private def extract_value(property : ASR::PropertyMetadataBase, data : ASR::Any, path : Tuple?) : ASR::Any?
          if path && (value = data.dig?(*path))
            return value
          end

           if (key = property.aliases.find { |a| data[a]? }) && (value = data[key]?)
            return value
          end

          if value = data[property.external_name]?
            return value
          end

          nil
        end
      {% end %}
    end
  end
end
