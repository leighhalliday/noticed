module Noticed
  module DeliveryMethods
    class Base < Noticed.parent_class.constantize
      extend ActiveModel::Callbacks
      define_model_callbacks :deliver

      class_attribute :option_names, instance_writer: false, default: []

      attr_reader :notification, :options, :params, :recipient, :record

      class << self
        # Copy option names from parent
        def inherited(base) # :nodoc:
          base.option_names = option_names.dup
          super
        end

        def options(*names)
          option_names.concat Array.wrap(names)
        end
        alias_method :option, :options

        def validate!(delivery_method_options)
          option_names.each do |option_name|
            unless delivery_method_options.key? option_name
              raise ValidationError, "option `#{option_name}` must be set for #{name}"
            end
          end
        end
      end

      def perform(args)
        @notification = args[:notification_class].constantize.new(args[:params])
        @options = args[:options] || {}
        @params = args[:params]
        @recipient = args[:recipient]
        @record = args[:record]

        # Make notification aware of database record and recipient during delivery
        @notification.record = args[:record]
        @notification.recipient = args[:recipient]

        return if (condition = @options[:if]) && !@notification.send(condition)
        return if (condition = @options[:unless]) && @notification.send(condition)

        run_callbacks :deliver do
          deliver
        end
      end

      def deliver
        raise NotImplementedError, "Delivery methods must implement a deliver method"
      end

      private

      # Helper method for making POST requests from delivery methods
      #
      # Usage:
      #   post("http://example.com", basic_auth: {user:, pass:}, json: {}, form: {})
      #
      def post(url, args = {})
        basic_auth = args.delete(:basic_auth)

        request = if basic_auth
          HTTP.basic_auth(user: basic_auth[:user], pass: basic_auth[:pass])
        else
          HTTP
        end

        response = request.post(url, args)

        if options[:debug]
          Rails.logger.debug("POST #{url}")
          Rails.logger.debug("Response: #{response.code}: #{response}")
        end

        if !options[:ignore_failure] && !response.status.success?
          raise ResponseUnsuccessful.new(response)
        end

        response
      end
    end
  end
end
