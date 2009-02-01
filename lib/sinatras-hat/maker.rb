module Sinatra
  module Hat
    # This is where it all comes together
    class Maker
      include Sinatra::Hat::Extendor
      include Sinatra::Authorization::Helpers
      
      attr_reader :klass, :app
      
      def self.actions
        @actions ||= { }
      end
      
      def self.action(name, path, options={}, &block)
        verb = options[:verb] || :get
        Router.cache << [verb, name, path]
        actions[name] = { :path => path, :verb => verb, :fn => block }
      end

      include Sinatra::Hat::Actions
      
      #  ======================================================
      
      def initialize(klass, overrides={})
        @klass = klass
        options.merge!(overrides)
        with(options)
      end
      
      # Simply stores the app instance when #mount is called.
      def setup(app)
        @app = app
      end
      
      # Processes a request, using the action specified in actions.rb
      #
      # TODO The work of handling a request should probably be wrapped
      #      up in a class.
      def handle(action, request)
        request.error(404) unless only.include?(action)
        protect!(request) if protect.include?(action)
        
        log_with_benchmark(request, action) do
          instance_exec(request, &self.class.actions[action][:fn])
        end
      end
      
      # Allows the DSL for specifying custom flow controls in a #mount
      # block by altering the responder's defaults hash.
      def after(action)
        yield HashMutator.new(responder.defaults[action])
      end
      
      # The finder block is used when loading all records for the index
      # action. It gets passed the model proxy and the request params hash.
      def finder(&block)
        if block_given?
          options[:finder] = block
        else
          options[:finder]
        end
      end
      
      # The finder block is used when loading a single record, which
      # is the case for most actions. It gets passed the model proxy
      # and the request params hash.
      def record(&block)
        if block_given?
          options[:record] = block
        else
          options[:record]
        end
      end
      
      # The authenticator block gets called before protected actions. It
      # gets passed the basic auth username and password.
      def authenticator(&block)
        if block_given?
          options[:authenticator] = block
        else
          options[:authenticator]
        end
      end
      
      # A list of actions that get generated by this maker instance. By
      # default it's all of the actions specified in actions.rb
      def only(*actions)
        if actions.empty?
          options[:only] ||= Set.new(options[:only])
        else
          Set.new(options[:only] = actions)
        end
      end
      
      # A list of actions to protect via basic auth. Protected actions
      # will have the authenticator block called before they are handled. 
      def protect(*actions)
        credentials.merge!(actions.extract_options!)
        
        if actions.empty?
          options[:protect] ||= Set.new([])
        else
          actions == [:all] ? 
            Set.new(options[:protect] = only) :
            Set.new(options[:protect] = actions)
        end
      end
      
      # The path prefix to use for routes and such.
      def prefix
        options[:prefix] ||= model.plural
      end
      
      # An array of parent Maker instances under which this instance
      # was nested.
      def parents
        @parents ||= parent ? Array(parent) + parent.parents : []
      end
      
      # Looks up the resource path for the specified arguments using this
      # maker's Resource instance.
      def resource_path(*args)
        resource.path(*args)
      end
      
      # Default options
      def options
        @options ||= {
          :only => Set.new(Maker.actions.keys),
          :parent => nil,
          :finder => proc { |model, params| model.all },
          :record => proc { |model, params| model.find_by_id(params[:id]) },
          :protect => [ ],
          :formats => { },
          :credentials => { :username => 'username', :password => 'password', :realm => "The App" },
          :authenticator => proc { |username, password| [username, password] == [:username, :password].map(&credentials.method(:[])) }
        }
      end

      # Generates routes in the context of the given app.
      def generate_routes!
        Router.new(self).generate(@app)
      end
      
      # The responder determines what kind of response should used for
      # a given action.
      #
      # TODO It might be better off to instantiate a new one of these per
      # request, instead of having one per maker instance.
      def responder
        @responder ||= Responder.new(self)
      end
      
      # Handles ORM/model related logic.
      def model
        @model ||= Model.new(self)
      end
      
      # TODO Hook this into Rack::CommonLogger
      def logger
        @logger ||= Logger.new(self)
      end
      
      private
      
      # Generates paths for this maker instance.
      def resource
        @resource ||= Resource.new(self)
      end
      
      def protected?(action)
        protect.include?(action)
      end
      
      # Handles a request with logging and benchmarking.
      def log_with_benchmark(request, action)
        msg = [ ]
        msg << "#{request.env['REQUEST_METHOD']} #{request.env['PATH_INFO']}"
        msg << "Params: #{request.params.inspect}"
        msg << "Action: #{action.to_s.upcase}"
        
        logger.info "[sinatras-hat] " + msg.join(' | ')
        
        result = nil
        
        t = Benchmark.realtime { result = yield }
        
        logger.info "               Request finished in #{t} sec."
        
        result
      end
    end
  end
end