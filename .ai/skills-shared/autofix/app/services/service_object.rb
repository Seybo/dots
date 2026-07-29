# frozen_string_literal: true

module ServiceObject
  def self.included(base)
    base.extend(ClassMethods)
  end

  module ClassMethods
    def argument_error_message(prefix, invalid_names, argument_names, args)
      "#{prefix} #{invalid_names} for #{name}; expected: #{argument_names}, received: #{args.keys}"
    end

    def call(**args, &block)
      new(**args).call(&block)
    end

    def arguments(*required_arguments, **optional_arguments)
      argument_names = required_arguments + optional_arguments.keys
      if argument_names.any?
        attr_reader(*argument_names)
        private(*argument_names)
      end

      define_method(:initialize) do |**args|
        missing_arguments = required_arguments - args.keys
        if missing_arguments.any?
          raise ArgumentError, self.class.argument_error_message(
            'Missing required arguments', missing_arguments, argument_names, args
          )
        end

        invalid_arguments = args.keys - argument_names
        if invalid_arguments.any?
          raise ArgumentError, self.class.argument_error_message(
            'Invalid arguments', invalid_arguments, argument_names, args
          )
        end

        optional_arguments.merge(args).each do |name, value|
          instance_variable_set(:"@#{name}", value)
        end
      end
    end
  end
end
