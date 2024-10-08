# frozen_string_literal: true
# rubocop:todo all

# Copyright (C) 2014-2020 MongoDB Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'mongo/collection/view/aggregation/behavior'

module Mongo
  class Collection
    class View

      # Provides behavior around an aggregation pipeline on a collection view.
      #
      # @since 2.0.0
      class Aggregation
        include Behavior

        # @return [ Array<Hash> ] pipeline The aggregation pipeline.
        attr_reader :pipeline

        # Initialize the aggregation for the provided collection view, pipeline
        # and options.
        #
        # @example Create the new aggregation view.
        #   Aggregation.view.new(view, pipeline)
        #
        # @param [ Collection::View ] view The collection view.
        # @param [ Array<Hash> ] pipeline The pipeline of operations.
        # @param [ Hash ] options The aggregation options.
        #
        # @option options [ true, false ] :allow_disk_use Set to true if disk
        #   usage is allowed during the aggregation.
        # @option options [ Integer ] :batch_size The number of documents to return
        #   per batch.
        # @option options [ true, false ] :bypass_document_validation Whether or
        #   not to skip document level validation.
        # @option options [ Hash ] :collation The collation to use.
        # @option options [ Object ] :comment A user-provided
        #   comment to attach to this command.
        # @option options [ String ] :hint The index to use for the aggregation.
        # @option options [ Hash ] :let Mapping of variables to use in the pipeline.
        #   See the server documentation for details.
        # @option options [ Integer ] :max_time_ms The maximum amount of time in
        #   milliseconds to allow the aggregation to run. This option is deprecated, use
        #   :timeout_ms instead.
        # @option options [ Session ] :session The session to use.
        # @option options [ :cursor_lifetime | :iteration ] :timeout_mode How to interpret
        #   :timeout_ms (whether it applies to the lifetime of the cursor, or per
        #   iteration).
        # @option options [ Integer ] :timeout_ms The operation timeout in milliseconds.
        #    Must be a non-negative integer. An explicit value of 0 means infinite.
        #    The default value is unset which means the value is inherited from
        #    the collection or the database or the client.
        #
        # @since 2.0.0
        def initialize(view, pipeline, options = {})
          perform_setup(view, options) do
            @pipeline = pipeline.dup
            unless Mongo.broken_view_aggregate || view.filter.empty?
              @pipeline.unshift(:$match => view.filter)
            end
          end
        end

        private

        def new(options)
          Aggregation.new(view, pipeline, options)
        end

        def initial_query_op(session, read_preference)
          Operation::Aggregate.new(aggregate_spec(session, read_preference))
        end

        # Return effective read preference for the operation.
        #
        # If the pipeline contains $merge or $out, and read preference specified
        # by user is secondary or secondary_preferred, and target server is below
        # 5.0, than this method returns primary read preference, because the
        # aggregation will be routed to primary. Otherwise return the original
        # read preference.
        #
        # See https://github.com/mongodb/specifications/blob/master/source/crud/crud.rst#read-preferences-and-server-selection
        #
        # @param [ Server::Connection ] connection The connection which
        #   will be used for the operation.
        # @return [ Hash | nil ] read preference hash that should be sent with
        #   this command.
        def effective_read_preference(connection)
          return unless view.read_preference
          return view.read_preference unless write?
          return view.read_preference unless [:secondary, :secondary_preferred].include?(view.read_preference[:mode])

          primary_read_preference = {mode: :primary}
          description = connection.description
          if description.primary?
            log_warn("Routing the Aggregation operation to the primary server")
            primary_read_preference
          elsif description.mongos? && !description.features.merge_out_on_secondary_enabled?
            log_warn("Routing the Aggregation operation to the primary server")
            primary_read_preference
          else
            view.read_preference
          end

        end

        def send_initial_query(server, context)
          if server.load_balancer?
            # Connection will be checked in when cursor is drained.
            connection = server.pool.check_out(context: context)
            initial_query_op(
              context.session,
              effective_read_preference(connection)
            ).execute_with_connection(
              connection,
              context: context
            )
          else
            server.with_connection do |connection|
              initial_query_op(
                context.session,
                effective_read_preference(connection)
              ).execute_with_connection(
                connection,
                context: context
              )
            end
          end
        end
      end
    end
  end
end
