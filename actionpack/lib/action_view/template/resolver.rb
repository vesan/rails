require "pathname"
require "active_support/core_ext/class"
require "action_view/template"

module ActionView
  # = Action View Resolver
  class Resolver
    def initialize
      @cached = Hash.new { |h1,k1| h1[k1] = Hash.new { |h2,k2|
        h2[k2] = Hash.new { |h3,k3| h3[k3] = Hash.new { |h4,k4| h4[k4] = {} } } } }
    end

    def clear_cache
      @cached.clear
    end

    # Normalizes the arguments and passes it on to find_template.
    def find_all(name, prefix=nil, partial=false, details={}, locals=[], key=nil)
      cached(key, prefix, name, partial, locals) do
        find_templates(name, prefix, partial, details)
      end
    end

  private

    def caching?
      @caching ||= !defined?(Rails.application) || Rails.application.config.cache_classes
    end

    # This is what child classes implement. No defaults are needed
    # because Resolver guarantees that the arguments are present and
    # normalized.
    def find_templates(name, prefix, partial, details)
      raise NotImplementedError
    end

    # Helpers that builds a path. Useful for building virtual paths.
    def build_path(name, prefix, partial, details)
      path = ""
      path << "#{prefix}/" unless prefix.empty?
      path << (partial ? "_#{name}" : name)
      path
    end

    # Get the handler and format from the given parameters.
    def retrieve_handler_and_format(handler, format, default_formats=nil)
      handler  = Template.handler_class_for_extension(handler)
      format   = format && Mime[format]
      format ||= handler.default_format if handler.respond_to?(:default_format)
      format ||= default_formats
      [handler, format]
    end

    def cached(key, prefix, name, partial, locals)
      locals = sort_locals(locals)
      unless key && caching?
        yield.each { |t| t.locals = locals }
      else
        @cached[key][prefix][name][partial][locals] ||= yield.each { |t| t.locals = locals }
      end
    end

    if :locale.respond_to?("<=>")
      def sort_locals(locals)
        locals.sort.freeze
      end
    else
      def sort_locals(locals)
        locals = locals.map{ |l| l.to_s }
        locals.sort!
        locals.freeze
      end
    end
  end

  class PathResolver < Resolver
    EXTENSION_ORDER = [:locale, :formats, :handlers]

    private

    def find_templates(name, prefix, partial, details)
      path = build_path(name, prefix, partial, details)
      query(path, EXTENSION_ORDER.map { |ext| details[ext] }, details[:formats])
    end

    def query(path, exts, formats)
      query = File.join(@path, path)

      exts.each do |ext|
        query << '{' << ext.map {|e| e && ".#{e}" }.join(',') << ',}'
      end

      Dir[query].reject { |p| File.directory?(p) }.map do |p|
        handler, format = extract_handler_and_format(p, formats)

        contents = File.open(p, "rb") {|io| io.read }

        Template.new(contents, File.expand_path(p), handler,
          :virtual_path => path, :format => format)
      end
    end

    # Extract handler and formats from path. If a format cannot be a found neither
    # from the path, or the handler, we should return the array of formats given
    # to the resolver.
    def extract_handler_and_format(path, default_formats)
      pieces = File.basename(path).split(".")
      pieces.shift
      retrieve_handler_and_format(pieces.pop, pieces.pop, default_formats)
    end
  end

  class FileSystemResolver < PathResolver
    def initialize(path)
      raise ArgumentError, "path already is a Resolver class" if path.is_a?(Resolver)
      super()
      @path = File.expand_path(path)
    end

    def to_s
      @path.to_s
    end
    alias :to_path :to_s

    def eql?(resolver)
      self.class.equal?(resolver.class) && to_path == resolver.to_path
    end
    alias :== :eql?
  end
end
