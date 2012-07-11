class Asari
  # Public: This module should be included in any class inheriting from
  # ActiveRecord::Base that needs to be indexed. Every time this module is
  # included, asari_index *must* be called (see below). Including this module
  # will automatically create before_destroy, after_create, and after_update AR
  # callbacks to remove, add, and update items in the CloudSearch index
  # (respectively).
  #
  module ActiveRecord
    def self.included(base)
      base.extend(ClassMethods)

      base.class_eval do
        before_destroy :asari_remove_from_index
        after_create :asari_add_to_index
        after_update :asari_update_in_index
      end
    end

    def asari_remove_from_index
      self.class.asari_remove_item(self)
    end

    def asari_add_to_index
      self.class.asari_add_item(self)
    end

    def asari_update_in_index
      self.class.asari_update_item(self)
    end

    module ClassMethods

      # Public: DSL method for adding this model object to the asari search
      # index.
      #
      # This method *must* be called in any object that includes
      # Asari::ActiveRecord, or your methods will be very sad.
      #
      #   search_domain - the CloudSearch domain to use for indexing this model.
      #   fields - an array of Symbols representing the list of fields that
      #     should be included in this index.
      #
      # Examples:
      #     class User < ActiveRecord::Base
      #       include Asari::ActiveRecord
      #
      #       asari_index("my-companies-users-asglkj4rsagkjlh34", [:name, :email])
      #
      def asari_index(search_domain, fields)
        self.class_variable_set(:@@asari, Asari.new(search_domain))
        self.class_variable_set(:@@fields, fields)
      end

      def asari_instance
        self.class_variable_get(:@@asari)
      end

      def asari_fields
        self.class_variable_get(:@@fields)
      end

      # Internal: method for adding a newly created item to the CloudSearch
      # index. Should probably only be called from asari_add_to_index above.
      def asari_add_item(obj)
        data = {}
        self.asari_fields.each do |field|
          data[field] = obj.send(field)
        end
        self.asari_instance.add_item(obj.send(:id), data)
      rescue Asari::DocumentUpdateException => e
        asari_on_error(e)
      end

      # Internal: method for updating a freshly edited item to the CloudSearch
      # index. Should probably only be called from asari_update_in_index above.
      def asari_update_item(obj)
        data = {}
        self.asari_fields.each do |field|
          data[field] = obj.send(field)
        end
        self.asari_instance.update_item(obj.send(:id), data)
      rescue Asari::DocumentUpdateException => e
        asari_on_error(e)
      end

      # Internal: method for removing a soon-to-be deleted item from the CloudSearch
      # index. Should probably only be called from asari_remove_from_index above.
      def asari_remove_item(obj)
        self.asari_instance.remove_item(obj.send(:id))
      rescue Asari::DocumentUpdateException => e
        asari_on_error(e)
      end

      # Public: method for searching the index for the specified term and
      #   returning all model objects that match. 
      #
      # Returns: a list of all matching AR model objects, or an empty list if no
      #   records are found that match.
      #
      # Raises: an Asari::SearchException error if there are issues
      #   communicating with the CloudSearch server.
      def asari_find(term)
        ids = self.asari_instance.search(term).map { |id| id.to_i }
        begin
          self.find(*ids)
        rescue ::ActiveRecord::RecordNotFound
          []
        end
      end

      # Public: method for handling errors from Asari document updates. By
      # default, this method causes all such exceptions (generated by issues
      # from updates, creates, or deletes to the index) to be raised immediately
      # to the caller; override this method on your activerecord object to
      # handle the errors in a custom fashion. Be sure to return true if you
      # don't want the AR callbacks to halt execution.
      #
      def asari_on_error(exception)
        raise exception
      end
    end
  end
end