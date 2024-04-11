# frozen_string_literal: true

module Mongo
  module Operation
    class DropSearchIndex
      # A MongoDB createSearchIndexes operation sent as an op message.
      #
      # @api private
      class OpMsg < OpMsgBase
        include ExecutableTransactionLabel

        private

        # Returns the command to send to the database, describing the
        # desired dropSearchIndex operation.
        #
        # @param [ Connection ] _connection the connection that the command
        #   will be executed on.
        # @param [ Operation::Context ] _context the context that is active
        #   for the command.
        #
        # @return [ Hash ] the selector
        def selector(_connection, _context)
          {
            dropSearchIndex: coll_name,
            :$db => db_name,
          }.tap do |sel|
            sel[:id] = index_id if index_id
            sel[:name] = index_name if index_name
          end
        end
      end
    end
  end
end
