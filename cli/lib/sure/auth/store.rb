# frozen_string_literal: true

require_relative "../errors"

module Sure
  module Auth
    # Internal failure from a credential backend or its helper process. It is
    # never rendered directly: StoreFactory turns it into a fallback or a
    # user-facing error.
    class StoreError < StandardError; end

    # Interface every credential backend implements. Plan 01-04 adds the OS
    # keychain and file implementations; this plan only ships NullStore so an
    # environment-only key can build a client before storage exists.
    class Store
      def read(_key)
        raise NotImplementedError, "#{self.class} must implement #read"
      end

      def write(_key, _credential)
        raise NotImplementedError, "#{self.class} must implement #write"
      end

      def delete(_key)
        raise NotImplementedError, "#{self.class} must implement #delete"
      end

      def mode
        raise NotImplementedError, "#{self.class} must implement #mode"
      end

      def location
        raise NotImplementedError, "#{self.class} must implement #location"
      end
    end

    # Safe placeholder until real storage lands: reads always miss and writes
    # fail loudly rather than silently discarding a credential.
    class NullStore < Store
      def read(_key)
        nil
      end

      def write(_key, _credential)
        raise Errors::GeneralError, "credential storage lands in Plan 01-04"
      end

      def delete(_key)
        raise Errors::GeneralError, "credential storage lands in Plan 01-04"
      end

      def mode
        :file
      end

      def location
        "unavailable"
      end
    end
  end
end
