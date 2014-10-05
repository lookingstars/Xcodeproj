require 'fiddle'

module Xcodeproj
  def self.read_plist(path)
    PlistHelper.read(path)
  end

  def self.write_plist(hash, path)
    PlistHelper.write(hash, path)
  end

  # Provides support for loading and serializing property list files.
  #
  module PlistHelper
    class << self
      # Serializes a hash as an XML property list file.
      #
      # @param  [#to_hash] hash
      #         The hash to store.
      #
      # @param  [#to_s] path
      #         The path of the file.
      #
      def write(hash, path)
        unless hash.is_a?(Hash)
          if hash.respond_to?(:to_hash)
            hash = hash.to_hash
          else
            raise TypeError, "The given `#{hash.inspect}` must be a hash or " \
                             "respond to #to_hash'."
          end
        end

        unless path.is_a?(String) || path.is_a?(Pathname)
          raise TypeError, "The given `#{path}` must be a string or 'pathname'."
        end
        path = path.to_s

        url = CoreFoundation.CFURLCreateFromFileSystemRepresentation(Fiddle::NULL, path, path.bytesize, CoreFoundation::FALSE)
        stream = CoreFoundation.CFWriteStreamCreateWithFile(Fiddle::NULL, url)
        unless CoreFoundation.CFWriteStreamOpen(stream) == CoreFoundation::TRUE
          raise "Unable to open stream!"
        end
        begin
          plist = CoreFoundation.RubyHashToCFDictionary(hash)

          error_ptr = Fiddle::Pointer.malloc(Fiddle::SIZEOF_INTPTR_T, CoreFoundation.free_function)
          result = CoreFoundation.CFPropertyListWrite(plist, stream, CoreFoundation::KCFPropertyListXMLFormat_v1_0, 0, error_ptr)
          if result == 0
            error = CoreFoundation.CFAutoRelease(error_ptr.ptr)
            CoreFoundation.CFShow(error)
            raise "Unable to write plist data!"
          end
        ensure
          CoreFoundation.CFWriteStreamClose(stream)
        end

        true
      end

      # @return [String] Returns the native objects loaded from a property list
      #         file.
      #
      # @param  [#to_s] path
      #         The path of the file.
      #
      def read(path)
        path = path.to_s
        unless File.exist?(path)
          raise ArgumentError, "The plist file at path `#{path}` doesn't exist."
        end

        url = CoreFoundation.CFURLCreateFromFileSystemRepresentation(Fiddle::NULL, path, path.bytesize, CoreFoundation::FALSE)
        stream = CoreFoundation.CFReadStreamCreateWithFile(Fiddle::NULL, url)
        unless CoreFoundation.CFReadStreamOpen(stream) == CoreFoundation::TRUE
          raise "Unable to open stream!"
        end
        plist = nil
        begin
          error_ptr = Fiddle::Pointer.malloc(Fiddle::SIZEOF_INTPTR_T, CoreFoundation.free_function)
          plist = CoreFoundation.CFPropertyListCreateWithStream(Fiddle::NULL, stream, 0, CoreFoundation::KCFPropertyListImmutable, Fiddle::NULL, error_ptr)
          if plist.null?
            error = CoreFoundation.CFAutoRelease(error_ptr.ptr)
            CoreFoundation.CFShow(error)
            raise "Unable to read plist data!"
          elsif CoreFoundation.CFGetTypeID(plist) != CoreFoundation.CFDictionaryGetTypeID()
            raise "Expected a plist with a dictionary root object!"
          end
        ensure
          CoreFoundation.CFReadStreamClose(stream)
        end
        CoreFoundation.CFDictionaryToRubyHash(plist)
      end

      private

      module CoreFoundation
        CFTypeRef = Fiddle::TYPE_VOIDP
        CFTypeRefPointer = Fiddle::TYPE_VOIDP
        SInt32Pointer = Fiddle::TYPE_VOIDP
        UInt8Pointer = Fiddle::TYPE_VOIDP
        CharPointer = Fiddle::TYPE_VOIDP
        CFIndex = Fiddle::TYPE_LONG
        CFTypeID = -Fiddle::TYPE_LONG

        CFPropertyListMutabilityOptions = Fiddle::TYPE_INT
        KCFPropertyListImmutable = 0

        CFPropertyListFormat = Fiddle::TYPE_INT
        KCFPropertyListXMLFormat_v1_0 = 100
        CFPropertyListFormatPointer = Fiddle::TYPE_VOIDP

        UInt32 = -Fiddle::TYPE_INT
        UInt8 = -Fiddle::TYPE_CHAR

        CFOptionFlags = UInt32

        CFStringEncoding = UInt32
        KCFStringEncodingUTF8 = 0x08000100

        Boolean = Fiddle::TYPE_CHAR
        TRUE = 1
        FALSE = 0

        FunctionPointer = Fiddle::TYPE_VOIDP

        def self.image
          @image ||= Fiddle.dlopen('/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation')
        end

        # C Ruby's free() function
        def self.free_function
          Fiddle::Function.new(Fiddle::RUBY_FREE, [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOID)
        end

        def self.CFRelease_function
          Fiddle::Function.new(image['CFRelease'], [CFTypeRef], Fiddle::TYPE_VOID)
        end

        # Made up function that assigns `CFRelease` as the function that should be
        # used to free the memory once Ruby's GC deems the object out of scope.
        def self.CFAutoRelease(ref)
          ref.free = CFRelease_function() unless ref.null?
          ref
        end

        def self.function(symbol, parameter_types, return_type)
          symbol = symbol.to_s
          create_function = symbol.include?('Create')
          function_cache_key = "@__#{symbol}__"

          define_singleton_method(symbol) do |*args|
            # Implement Ruby method calling semantics regarding method signature.
            unless args.size == parameter_types.size
              raise ArgumentError, "wrong number of arguments (#{args.size} for #{parameter_types.size})"
            end

            # Get cached function or cache a new function instance.
            unless function = instance_variable_get(function_cache_key)
              function = Fiddle::Function.new(image[symbol.to_s], parameter_types, return_type)
              instance_variable_set(function_cache_key, function)
            end

            result = function.call(*args)
            create_function ? CFAutoRelease(result) : result
          end
        end

        # Actual function wrappers

        function :CFShow,
                 [CFTypeRef],
                 Fiddle::TYPE_VOID

        function :CFDictionaryApplyFunction,
                 [CFTypeRef, FunctionPointer, Fiddle::TYPE_VOIDP],
                 Fiddle::TYPE_VOID

        function :CFWriteStreamCreateWithFile,
                 [CFTypeRef, CFTypeRef],
                 CFTypeRef

        function :CFWriteStreamOpen,
                 [CFTypeRef],
                 Boolean

        function :CFWriteStreamClose,
                 [CFTypeRef],
                 Fiddle::TYPE_VOID

        function :CFReadStreamCreateWithFile,
                 [CFTypeRef, CFTypeRef],
                 CFTypeRef

        function :CFReadStreamOpen,
                 [CFTypeRef],
                 Boolean

        function :CFReadStreamClose,
                 [CFTypeRef],
                 Fiddle::TYPE_VOID

        function :CFPropertyListWrite,
                 [CFTypeRef, CFTypeRef, CFPropertyListFormat, CFOptionFlags, CFTypeRefPointer],
                 CFIndex

        function :CFURLCreateFromFileSystemRepresentation,
                 [CFTypeRef, UInt8Pointer, CFIndex, Boolean],
                 CFTypeRef

        function :CFPropertyListCreateWithStream,
                 [CFTypeRef, CFTypeRef, CFIndex, CFOptionFlags, CFPropertyListFormatPointer, CFTypeRefPointer],
                 CFTypeRef

        function :CFArrayGetCount,
                 [CFTypeRef],
                 CFIndex

        function :CFArrayGetValueAtIndex,
                 [CFTypeRef, CFIndex],
                 CFTypeRef

        function :CFGetTypeID,
                 [CFTypeRef],
                 CFTypeID

        function :CFDictionaryGetTypeID, [], CFTypeID
        function :CFStringGetTypeID, [], CFTypeID
        function :CFArrayGetTypeID, [], CFTypeID
        function :CFBooleanGetTypeID, [], CFTypeID

        function :CFStringCreateExternalRepresentation,
                 [CFTypeRef, CFTypeRef, CFStringEncoding, UInt8],
                 CFTypeRef

        function :CFStringCreateWithCString,
                 [CFTypeRef, CharPointer, CFStringEncoding],
                 CFTypeRef

        function :CFDataGetLength,
                 [CFTypeRef],
                 CFIndex

        function :CFDataGetBytePtr,
                 [CFTypeRef],
                 Fiddle::TYPE_VOIDP

        function :CFDictionaryCreateMutable,
                 [CFTypeRef, CFIndex, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
                 CFTypeRef

        function :CFDictionaryAddValue,
                 [CFTypeRef, CFTypeRef, CFTypeRef],
                 Fiddle::TYPE_VOIDP

        function :CFArrayCreateMutable,
                 [CFTypeRef, CFIndex, Fiddle::TYPE_VOIDP],
                 CFTypeRef

        function :CFArrayAppendValue,
                 [CFTypeRef, CFTypeRef],
                 Fiddle::TYPE_VOIDP

        function :CFCopyDescription,
                 [CFTypeRef],
                 CFTypeRef

        function :CFBooleanGetValue,
                 [CFTypeRef],
                 Boolean

        # Custom convenience wrappers

        def self.CFDictionaryApplyBlock(dictionary, &applier)
          raise "Callback block required!" if applier.nil?
          param_types = [CFTypeRef, CFTypeRef, Fiddle::TYPE_VOIDP]
          closure = Fiddle::Closure::BlockCaller.new(Fiddle::TYPE_VOID, param_types, &applier)
          closure_function = Fiddle::Function.new(closure, param_types, Fiddle::TYPE_VOID)
          CFDictionaryApplyFunction(dictionary, closure_function, Fiddle::NULL)
        end

        # TODO Couldn't figure out how to pass a CFRange struct by reference to the
        #      real `CFArrayApplyFunction` function, so cheating by implementing our
        #      own version.
        def self.CFArrayApplyBlock(array)
          raise "Callback block required!" unless block_given?
          CFArrayGetCount(array).times do |index|
            yield CFArrayGetValueAtIndex(array, index)
          end
        end

        # CFTypeRef to Ruby conversions

        def self.CFTypeRefToRubyValue(ref)
          case CFGetTypeID(ref)
          when CFStringGetTypeID()
            CFStringToRubyString(ref)
          when CFDictionaryGetTypeID()
            CFDictionaryToRubyHash(ref)
          when CFArrayGetTypeID()
            CFArrayToRubyArray(ref)
          when CFBooleanGetTypeID()
            CFBooleanToRubyBoolean(ref)
          else
            description = CFStringToRubyString(CFCopyDescription(ref))
            raise TypeError, "Unknown type: #{description}"
          end
        end

        # TODO Does Pointer#to_str actually copy the data as expected?
        def self.CFStringToRubyString(string)
          data = CFStringCreateExternalRepresentation(Fiddle::NULL, string, KCFStringEncodingUTF8, 0)
          if data.null?
            raise "Unable to convert string!"
          end
          bytes_ptr = CFDataGetBytePtr(data)
          s = bytes_ptr.to_str(CFDataGetLength(data))
          s.force_encoding(Encoding::UTF_8)
          s
        end

        def self.CFDictionaryToRubyHash(dictionary)
          result = {}
          CFDictionaryApplyBlock(dictionary) do |key, value|
            result[CFStringToRubyString(key)] = CFTypeRefToRubyValue(value)
          end
          result
        end

        def self.CFArrayToRubyArray(array)
          result = []
          CFArrayApplyBlock(array) do |element|
            result << CFTypeRefToRubyValue(element)
          end
          result
        end

        def self.CFBooleanToRubyBoolean(boolean)
          CFBooleanGetValue(boolean) == TRUE
        end

        # Ruby to CFTypeRef conversions

        def self.RubyValueToCFTypeRef(value)
          result = case value
                   when String
                     RubyStringToCFString(value)
                   when Hash
                     RubyHashToCFDictionary(value)
                   when Array
                     RubyArrayToCFArray(value)
                   when true, false
                     RubyBooleanToCFBoolean(value)
                   else
                     RubyStringToCFString(value.to_s)
                   end
          if result.null?
            raise TypeError, "Unable to convert Ruby value `#{value.inspect}' into a CFTypeRef."
          end
          result
        end

        def self.RubyStringToCFString(string)
          CFStringCreateWithCString(Fiddle::NULL, Fiddle::Pointer[string], KCFStringEncodingUTF8)
        end

        def self.RubyHashToCFDictionary(hash)
          dictionary = CFDictionaryCreateMutable(Fiddle::NULL, 0, image['kCFTypeDictionaryKeyCallBacks'], image['kCFTypeDictionaryValueCallBacks'])
          hash.each do |key, value|
            key = RubyStringToCFString(key.to_s)
            value = RubyValueToCFTypeRef(value)
            CFDictionaryAddValue(dictionary, key, value)
          end
          dictionary
        end

        def self.RubyArrayToCFArray(array)
          result = CFArrayCreateMutable(Fiddle::NULL, 0, image['kCFTypeArrayCallBacks'])
          array.each do |element|
            element = RubyValueToCFTypeRef(element)
            CFArrayAppendValue(result, element)
          end
          result
        end

        # Ah yeah, CFBoolean, it's not a CFNumber, it’s not a CFTypeRef. The
        # only way to get them easily is by using the constants, so load their
        # addresses as pointers and dereference them.
        def self.RubyBooleanToCFBoolean(value)
          Fiddle::Pointer.new(value ? image['kCFBooleanTrue'] : image['kCFBooleanFalse']).ptr
        end
      end

    end
  end
end

